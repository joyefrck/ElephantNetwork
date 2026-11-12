import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'update_release.dart';

final class UpdateTask {
  const UpdateTask(this.id, this.release, this.file);

  final String id;
  final UpdateRelease release;
  final File file;
}

class UpdateStore {
  UpdateStore(this.root);

  final Future<Directory> root;

  Future<Directory> _directory() async {
    final directory = await root;
    await directory.create(recursive: true);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Invalid update directory');
    }
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<UpdateTask> create(UpdateRelease release) async {
    final directory = await _directory();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final taskDirectory = await Directory(p.join(directory.path, id)).create();
    return UpdateTask(
      id,
      release,
      File(p.join(taskDirectory.path, 'installer.${release.extension}')),
    );
  }

  Future<void> save(UpdateTask task) async {
    await verify(task);
    final directory = await _directory();
    final pending = File(p.join(directory.path, 'pending.json.part'));
    await pending.writeAsString(
      jsonEncode({'id': task.id, 'release': task.release.toJson()}),
      flush: true,
    );
    await pending.rename(p.join(directory.path, 'pending.json'));
  }

  Future<UpdateTask?> recover() async {
    final directory = await _directory();
    final pending = File(p.join(directory.path, 'pending.json'));
    if (!await pending.exists()) return null;
    try {
      if (await pending.length() > 64 * 1024) {
        throw const FormatException('Invalid pending task');
      }
      final json = jsonDecode(await pending.readAsString()) as Map;
      final id = json['id'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
        throw const FormatException('Invalid task id');
      }
      final release = UpdateRelease.fromJson(
        Map<String, dynamic>.from(json['release'] as Map),
      );
      final task = UpdateTask(
        id,
        release,
        File(p.join(directory.path, id, 'installer.${release.extension}')),
      );
      await verify(task);
      return task;
    } on Object {
      await pending.delete();
      return null;
    }
  }

  Future<void> verify(UpdateTask task, {File? file}) async {
    final directory = await _directory();
    final expected = p.join(
      directory.path,
      task.id,
      'installer.${task.release.extension}',
    );
    final artifact = file ?? task.file;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(task.id) ||
        task.file.path != expected ||
        (artifact.path != expected && artifact.path != '$expected.part') ||
        await FileSystemEntity.type(p.dirname(expected), followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(artifact.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await artifact.length() != task.release.size) {
      throw const FormatException('Invalid update artifact');
    }
    final path = artifact.path;
    final hash = await Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
    if (hash != task.release.sha256) {
      throw const FormatException('Update checksum mismatch');
    }
  }

  Future<void> discard(UpdateTask task) async {
    final directory = await _directory();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(task.id)) return;
    final taskDirectory = Directory(p.join(directory.path, task.id));
    if (await FileSystemEntity.type(taskDirectory.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await taskDirectory.delete(recursive: true);
    }
    final pending = File(p.join(directory.path, 'pending.json'));
    if (await pending.exists()) {
      final json = jsonDecode(await pending.readAsString()) as Map;
      if (json['id'] == task.id) await pending.delete();
    }
  }
}
