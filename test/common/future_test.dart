import 'dart:async';

import 'package:fl_clash/common/future.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
