import 'dart:io';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'data_mutation.dart';

import 'package:archive/archive_io.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart' as p;

final class StagedRestore {
  const StagedRestore({required this.data, required this.directory});

  final MigrationData data;
  final String directory;
}

String backupEntryPath(String name) {
  final normalized = p.posix.normalize(name.replaceAll('\\', '/'));
  if (name.isEmpty ||
      name.contains('\u0000') ||
      p.posix.isAbsolute(normalized) ||
      p.windows.isAbsolute(name) ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.contains(':')) {
    throw const FormatException('Invalid backup entry path');
  }
  return normalized;
}

Future<void> extractBackupArchive(Archive archive, Directory directory) async {
  final entries = <String>{};
  var total = 0;
  if (archive.length > 100000) {
    throw const FormatException('Too many backup entries');
  }
  for (final entry in archive) {
    final path = backupEntryPath(entry.name);
    final key = path.toLowerCase();
    if (!entries.add(key) || entry.isSymbolicLink || entry.size < 0) {
      throw const FormatException('Invalid backup entry');
    }
    total += entry.size;
    if (total > 1024 * 1024 * 1024) {
      throw const FormatException('Backup exceeds size limit');
    }
  }
  for (final entry in archive) {
    final target = p.join(directory.path, backupEntryPath(entry.name));
    if (entry.isDirectory) {
      await Directory(target).create(recursive: true);
      continue;
    }
    await Directory(p.dirname(target)).create(recursive: true);
    final output = _BackupOutput(target, entry.size);
    try {
      entry.writeContent(output);
      if (output.length != entry.size ||
          (entry.crc32 != null && output.crc != entry.crc32)) {
        throw const FormatException('Backup entry checksum or size mismatch');
      }
    } finally {
      await output.close();
    }
  }
}

class _BackupOutput extends OutputFileStream {
  _BackupOutput(String path, this.maximum)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int maximum;
  int crc = 0;

  void _check(int count) {
    if (count < 0 || length + count > maximum) {
      throw const FormatException('Backup entry exceeds declared size');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    crc = getCrc32([value], crc);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _check(count);
    crc = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      crc,
    );
    super.writeBytes(bytes, length: count);
  }
}

String configurationDigest(Map<String, Object?>? configuration) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return sha256
      .convert(
        utf8.encode(
          jsonEncode(canonical(jsonDecode(jsonEncode(configuration)))),
        ),
      )
      .toString();
}

bool shouldRecoverConfiguration(
  Map<String, Object?>? current,
  Config pending,
  String? previousDigest,
) {
  if (previousDigest == null) return true;
  final currentDigest = configurationDigest(current);
  return currentDigest == previousDigest ||
      currentDigest ==
          configurationDigest(Map<String, Object?>.from(pending.toJson()));
}

class RestoreFileTransaction {
  RestoreFileTransaction({
    required this.stagingRoot,
    required this.activeRoot,
    required this.files,
    this.pendingConfig,
    this.previousConfigDigest,
  });

  final String stagingRoot;
  final String activeRoot;
  final Iterable<String> files;
  final Config? pendingConfig;
  final String? previousConfigDigest;
  final List<_RestoredFile> _changes = [];
  Directory? _undo;
  bool recoveryRequired = false;

  String? get id => _undo == null ? null : p.basename(_undo!.path);

  static bool _validName(String name) =>
      RegExp(r'^(profiles/[0-9]+\.yaml|scripts/[0-9]+\.js)$').hasMatch(name);

  Future<void> validate() async {
    final staging = await Directory(stagingRoot).resolveSymbolicLinks();
    final names = <String>{};
    for (final name in files) {
      if (!_validName(name) || !names.add(name)) {
        throw const FormatException('Invalid restored file identity');
      }
      final file = File(p.join(staging, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !p.isWithin(staging, await file.resolveSymbolicLinks())) {
        throw const FormatException('Restored configuration file is missing');
      }
    }
  }

  Future<void> _saveJournal() async {
    final directory = _undo!;
    final journal = File(p.join(directory.path, 'journal.json.part'));
    await journal.writeAsString(
      jsonEncode({
        'id': id,
        if (pendingConfig != null) 'config': pendingConfig!.toJson(),
        if (previousConfigDigest != null)
          'previousConfigDigest': previousConfigDigest,
        'files': [
          for (final change in _changes)
            {
              'path': change.relative,
              'backup': change.backup == null
                  ? null
                  : p.basename(change.backup!.path),
              'sha256': change.sha256,
            },
        ],
      }),
      flush: true,
    );
    await journal.rename(p.join(directory.path, 'journal.json'));
  }

  Future<void> apply() async {
    await validate();
    if (_undo != null) throw StateError('Restore files were already applied');
    final root = await Directory(activeRoot).resolveSymbolicLinks();
    final recovery = Directory(p.join(root, '.restore-recovery'));
    await recovery.create(recursive: true);
    if (await FileSystemEntity.type(recovery.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Invalid recovery directory');
    }
    _undo = await recovery.createTemp('restore-');
    await _saveJournal();
    for (final name in files) {
      final destination = File(p.join(root, name));
      await _validateDestination(root, destination);
      final exists = await destination.exists();
      File? backup;
      String? digest;
      if (exists) {
        backup = await destination.copy(
          p.join(_undo!.path, '${_changes.length}'),
        );
        digest = await _digest(backup);
      }
      _changes.add(_RestoredFile(name, destination, backup, digest));
      await _saveJournal();
      await replaceDataFile(File(p.join(stagingRoot, name)), destination);
    }
  }

  static Future<void> _validateDestination(String root, File file) async {
    if (await FileSystemEntity.type(file.parent.path, followLinks: false) ==
            FileSystemEntityType.link &&
        !p.isWithin(root, await file.parent.resolveSymbolicLinks())) {
      throw const FormatException('Restored target escapes application data');
    }
    await file.parent.create(recursive: true);
    if (!p.isWithin(root, await file.parent.resolveSymbolicLinks())) {
      throw const FormatException('Restored target escapes application data');
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw const FormatException('Invalid restore target');
    }
  }

  static Future<String> _digest(File file) {
    final path = file.path;
    return Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
  }

  Future<void> rollback() async {
    Object? firstError;
    for (final change in _changes.reversed) {
      try {
        final backup = change.backup;
        if (backup == null) {
          if (await change.destination.exists()) {
            await change.destination.delete();
          }
        } else if (await backup.exists()) {
          if (await _digest(backup) != change.sha256) {
            throw const FormatException('Recovery backup checksum mismatch');
          }
          try {
            await backup.rename(change.destination.path);
          } on FileSystemException {
            await replaceDataFile(backup, change.destination);
          }
        } else if (!await change.destination.exists() ||
            await _digest(change.destination) != change.sha256) {
          throw const FileSystemException('Recovery backup is missing');
        }
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    recoveryRequired = firstError != null;
    if (firstError != null) {
      throw FileSystemException(
        'Restore rollback failed; recovery files retained in ${_undo?.path}',
        '$firstError',
      );
    }
    _changes.clear();
  }

  Future<void> commit() async {
    _changes.clear();
    final undo = _undo;
    try {
      if (undo != null && await undo.exists()) {
        await undo.delete(recursive: true);
      }
    } on FileSystemException {
      recoveryRequired = true;
    }
  }

  static Future<void> recover({
    required String activeRoot,
    required Future<bool> Function(String id) isCommitted,
    required Future<void> Function(String id) forgetCommit,
    required Future<void> Function(Config config, String? previousDigest)
    persistConfig,
  }) async {
    final root = await Directory(activeRoot).resolveSymbolicLinks();
    final recovery = Directory(p.join(root, '.restore-recovery'));
    if (!await recovery.exists()) return;
    if (await FileSystemEntity.type(recovery.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Invalid recovery directory');
    }
    await for (final entity in recovery.list()) {
      final id = p.basename(entity.path);
      if (!id.startsWith('restore-') ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
        continue;
      }
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Invalid recovery task');
      }
      final directory = Directory(entity.path);
      final journal = File(p.join(directory.path, 'journal.json'));
      if (!await journal.exists()) {
        await directory.delete(recursive: true);
        await forgetCommit(id);
        continue;
      }
      if (await journal.length() > 64 * 1024 * 1024 ||
          await FileSystemEntity.type(journal.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const FormatException('Invalid recovery journal');
      }
      final value = jsonDecode(await journal.readAsString()) as Map;
      if (value['id'] != id || value['files'] is! List) {
        throw const FormatException('Invalid recovery journal');
      }
      final config = value['config'] == null
          ? null
          : Config.fromJson(Map<String, Object?>.from(value['config'] as Map));
      final transaction = RestoreFileTransaction(
        stagingRoot: directory.path,
        activeRoot: root,
        files: const [],
        pendingConfig: config,
        previousConfigDigest: value['previousConfigDigest'] as String?,
      ).._undo = directory;
      final paths = <String>{};
      for (final entry in value['files'] as List) {
        final relative = entry['path'] as String;
        final backupName = entry['backup'] as String?;
        final digest = entry['sha256'] as String?;
        if (!_validName(relative) ||
            !paths.add(relative) ||
            (backupName != null &&
                (!RegExp(r'^[0-9]+$').hasMatch(backupName) ||
                    digest == null ||
                    !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)))) {
          throw const FormatException('Invalid recovery file');
        }
        final destination = File(p.join(root, relative));
        await _validateDestination(root, destination);
        final backup = backupName == null
            ? null
            : File(p.join(directory.path, backupName));
        if (backup != null &&
            await FileSystemEntity.type(backup.path, followLinks: false) ==
                FileSystemEntityType.link) {
          throw const FormatException('Invalid recovery file type');
        }
        transaction._changes.add(
          _RestoredFile(relative, destination, backup, digest),
        );
      }
      if (await isCommitted(id)) {
        if (config != null) {
          await persistConfig(config, transaction.previousConfigDigest);
        }
      } else {
        await transaction.rollback();
      }
      await transaction.commit();
      if (transaction.recoveryRequired) {
        throw FileSystemException(
          'Recovery cleanup is pending',
          directory.path,
        );
      }
      await forgetCommit(id);
    }
  }
}

final class _RestoredFile {
  const _RestoredFile(
    this.relative,
    this.destination,
    this.backup,
    this.sha256,
  );
  final String relative;
  final File destination;
  final File? backup;
  final String? sha256;
}
