import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'method.dart';

const coreSpillDirectoryName = 'responses';

final coreSpillStore = CoreSpillStore(
  () async => p.join(await appPath.homeDirPath, coreSpillDirectoryName),
);

class CoreSpillStore {
  final Future<String> Function() directory;

  CoreSpillStore(this.directory);

  Future<bool> _contains(String path) async {
    final root = await directory();
    if (await FileSystemEntity.type(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    if (!p.equals(p.dirname(path), root) ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
      return false;
    }
    return p.equals(
      p.dirname(await File(path).resolveSymbolicLinks()),
      await Directory(root).resolveSymbolicLinks(),
    );
  }

  Future<CoreMethodResponse> resolve(CoreMethodResponse response) async {
    final path = response.file;
    if (path == null) return response;
    try {
      if (!await _contains(path)) {
        throw const FormatException('Response file is outside Core storage');
      }
      final decoded = CoreMethodResponse.fromJson(
        await compute(_readResponse, path),
      );
      if (decoded.id != response.id || decoded.file != null) {
        throw const FormatException('Response file does not match request');
      }
      return decoded;
    } catch (error) {
      return CoreMethodResponse(
        id: response.id,
        error: CoreMethodError(code: 'spill_error', message: '$error'),
      );
    }
  }

  Future<void> discard(CoreMethodResponse response) async {
    final path = response.file;
    if (path == null) return;
    try {
      if (await _contains(path)) await File(path).delete();
    } on FileSystemException catch (_) {}
  }
}

Map<String, Object?> _readResponse(String path) {
  final file = File(path);
  try {
    return Map<String, Object?>.from(
      json.decode(utf8.decode(file.readAsBytesSync())) as Map,
    );
  } finally {
    file.deleteSync();
  }
}
