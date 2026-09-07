import 'dart:async';

import 'package:fl_clash/common/future.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runMedianIntAttempts', () {
    test('returns the median successful value', () async {
      final values = [701, 216, 370];

      final result = await runMedianIntAttempts(
        attempts: 3,
        task: () async => values.removeAt(0),
      );

      expect(result, 370);
    });

    test('ignores failed and non-positive attempts', () async {
      var attempt = 0;
      final errors = <Object>[];

      final result = await runMedianIntAttempts(
        attempts: 3,
        task: () async {
          attempt++;
          if (attempt == 1) {
            throw StateError('failed');
          }
          return attempt == 2 ? -1 : 216;
        },
        onError: (error, _) => errors.add(error),
      );

      expect(result, 216);
      expect(errors, hasLength(1));
    });

    test('returns -1 when every attempt fails', () async {
      final result = await runMedianIntAttempts(
        attempts: 3,
        task: () async => throw StateError('failed'),
      );

      expect(result, -1);
    });

    test('rejects a non-positive attempt count', () {
      expect(
        () => runMedianIntAttempts(attempts: 0, task: () async => 1),
        throwsArgumentError,
      );
    });
  });

  test('runStaggeredBatches limits concurrent work to each batch', () async {
    final gates = List.generate(3, (_) => Completer<void>());
    final started = <int>[];
    var active = 0;
    var maxActive = 0;

    final result = runStaggeredBatches(
      items: List.generate(25, (index) => index),
      maxConcurrent: 10,
      staggerInterval: const Duration(milliseconds: 20),
      wait: (_) async {},
      task: (item) async {
        active++;
        maxActive = active > maxActive ? active : maxActive;
        started.add(item);
        await gates[item ~/ 10].future;
        active--;
      },
    );

    await _waitFor(() => started.length == 10);
    expect(started, List.generate(10, (index) => index));
    expect(maxActive, 10);

    gates[0].complete();
    await _waitFor(() => started.length == 20);
    expect(started, List.generate(20, (index) => index));
    expect(maxActive, 10);

    gates[1].complete();
    await _waitFor(() => started.length == 25);
    expect(started, List.generate(25, (index) => index));
    expect(maxActive, 10);

    gates[2].complete();
    await result;
  });

  test('runStaggeredBatches offsets work inside each batch', () async {
    final waits = <Duration>[];

    await runStaggeredBatches(
      items: [1, 2, 3],
      maxConcurrent: 3,
      staggerInterval: const Duration(milliseconds: 20),
      wait: (duration) async => waits.add(duration),
      task: (_) async {},
    );

    expect(waits, const [
      Duration(milliseconds: 20),
      Duration(milliseconds: 40),
    ]);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}
