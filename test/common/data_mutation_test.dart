import 'dart:async';

import 'package:fl_clash/common/data_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restore waits for an in-flight subscription mutation and supports nested writes',
    () async {
      final queue = DataMutationQueue();
      final started = Completer<void>();
      final network = Completer<void>();
      final calls = <String>[];
      final subscription = queue.run(() async {
        started.complete();
        await network.future;
        await queue.run(() async => calls.add('profile file'));
        calls.add('profile database');
      });
      await started.future;
      final restore = queue.run(() async => calls.add('restore'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      network.complete();
      await Future.wait([subscription, restore]);
      expect(calls, ['profile file', 'profile database', 'restore']);
    },
  );

  test('a failed mutation releases queued work', () async {
    final queue = DataMutationQueue();
    final failed = queue.run<void>(() async => throw StateError('failed'));
    final checked = expectLater(failed, throwsStateError);
    var nextRan = false;
    await queue.run(() async => nextRan = true);
    await checked;
    await queue.idle;
    expect(nextRan, isTrue);
  });
}
