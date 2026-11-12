import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

class DataMutationQueue {
  final Object _zoneKey = Object();
  Future<void> _tail = Future.value();

  Future<void> get idle => _tail;
  bool get isCurrent => Zone.current[_zoneKey] == this;

  Future<T> run<T>(Future<T> Function() action) async {
    if (Zone.current[_zoneKey] == this) return action();
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      return await runZoned(action, zoneValues: {_zoneKey: this});
    } finally {
      completed.complete();
    }
  }
}

Future<void> replaceDataFile(File source, File destination) async {
  await destination.parent.create(recursive: true);
  final temporary = await destination.parent.createTemp('.restore-');
  try {
    final file = await source.copy(p.join(temporary.path, 'payload'));
    await file.rename(destination.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

final dataMutationQueue = DataMutationQueue();
