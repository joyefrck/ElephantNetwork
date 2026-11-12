import 'dart:io';

import 'package:fl_clash/common/common.dart';

class SingleInstanceLock {
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;
  Future<bool>? _pending;
  final Future<String> Function() _resolvePath;

  SingleInstanceLock._internal() : _resolvePath = (() => appPath.lockFilePath);

  SingleInstanceLock.forTesting(this._resolvePath);

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  Future<bool> acquire() {
    return _pending ??= _acquire().then(
      (acquired) {
        if (!acquired) _pending = null;
        return acquired;
      },
      onError: (Object error, StackTrace stack) {
        _pending = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<bool> _acquire() async {
    if (_accessFile != null) return true;
    final file = File(await _resolvePath());
    await file.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock();
      _accessFile = handle;
      return true;
    } on FileSystemException catch (error) {
      await handle.close();
      if (const [11, 13, 33, 35].contains(error.osError?.errorCode)) {
        return false;
      }
      rethrow;
    } on Object {
      await handle.close();
      rethrow;
    }
  }

  Future<void> release() async {
    final file = _accessFile;
    _accessFile = null;
    _pending = null;
    if (file != null) await file.close();
  }
}

final singleInstanceLock = SingleInstanceLock();
