import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/common/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('elephant-backup-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'rejects absolute, traversal, drive and duplicate paths before extraction',
    () async {
      for (final path in [
        '../escaped',
        '/escaped',
        r'C:\escaped',
        r'..\escaped',
        r'\\server\share',
      ]) {
        final archive = Archive()..addFile(ArchiveFile.string(path, 'invalid'));
        await expectLater(
          extractBackupArchive(archive, root),
          throwsFormatException,
        );
        expect(await root.list().toList(), isEmpty);
      }
      final archive = Archive()
        ..addFile(ArchiveFile.string('config.json', '{}'))
        ..addFile(ArchiveFile.string('CONFIG.json', '{}'));
      await expectLater(
        extractBackupArchive(archive, root),
        throwsFormatException,
      );
      expect(await root.list().toList(), isEmpty);
      expect(backupEntryPath(r'profiles\1.yaml'), 'profiles/1.yaml');
    },
  );

  test(
    'rejects links, oversized archives and damaged entry checksums',
    () async {
      final link = ArchiveFile.string('profiles/link', '')
        ..symbolicLink = '/outside';
      await expectLater(
        extractBackupArchive(Archive()..addFile(link), root),
        throwsFormatException,
      );
      final oversized = ArchiveFile(
        'huge',
        1024 * 1024 * 1024 + 1,
        const <int>[],
      );
      await expectLater(
        extractBackupArchive(Archive()..addFile(oversized), root),
        throwsFormatException,
      );
      final damaged = ArchiveFile.string('config.json', '{}')..crc32 = 12345;
      await expectLater(
        extractBackupArchive(Archive()..addFile(damaged), root),
        throwsFormatException,
      );
    },
  );

  test('valid nested files extract without changing their contents', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('profiles/1.yaml', 'proxies: []'))
      ..addFile(
        ArchiveFile.string('scripts/2.js', 'function main(c) {return c;}'),
      );
    final encoded = ZipEncoder().encode(archive);
    final decoded = ZipDecoder().decodeBytes(encoded);
    await extractBackupArchive(decoded, root);
    expect(
      await File('${root.path}/profiles/1.yaml').readAsString(),
      'proxies: []',
    );
    expect(
      await File('${root.path}/scripts/2.js').readAsString(),
      contains('return c'),
    );
  });

  test(
    'snapshot archive round-trips through the real staging reader',
    () async {
      final home = await Directory(
        '${root.path}/home/profiles',
      ).create(recursive: true);
      await File('${home.path}/1.yaml').writeAsString('proxies: []');
      final source = Database(NativeDatabase.memory());
      final snapshot = File('${root.path}/snapshot.sqlite');
      try {
        await source.profilesDao.setAll([
          const Profile(
            id: 1,
            label: 'Preserved',
            profileType: ProfileType.custom,
            autoUpdateDuration: Duration.zero,
          ),
        ]);
        await source.createBackup(snapshot.path);
      } finally {
        await source.close();
      }
      final config =
          jsonDecode(
                jsonEncode(
                  const Config(
                    themeProps: ThemeProps(),
                    currentProfileId: 1,
                  ).toJson(),
                ),
              )
              as Map<String, dynamic>;
      config['version'] = 1;
      final archive = await createBackupArchive(
        configMap: config,
        snapshotPath: snapshot.path,
        homeRoot: home.parent.path,
        outputPath: '${root.path}/backup.zip',
        temporaryConfigPath: '${root.path}/config.tmp',
      );
      final staged = await stageBackup(
        backupFilePath: archive,
        stagingRoot: '${root.path}/staging',
      );
      expect(staged.data.profiles.single.label, 'Preserved');
      expect(staged.data.profiles.single.type, ProfileType.custom);
      expect(
        await File('${staged.directory}/profiles/1.yaml').readAsString(),
        'proxies: []',
      );
      expect(await File('${home.path}/1.yaml').readAsString(), 'proxies: []');
      expect(await File('${root.path}/config.tmp').exists(), isFalse);
    },
  );

  test(
    'future backup formats are rejected and their staging directory is removed',
    () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string('config.json', jsonEncode({'version': 999})),
        );
      final zip = File('${root.path}/backup.zip');
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      final staging = Directory('${root.path}/restore');
      await expectLater(
        stageBackup(backupFilePath: zip.path, stagingRoot: staging.path),
        throwsFormatException,
      );
      expect(await staging.list().toList(), isEmpty);
    },
  );
}
