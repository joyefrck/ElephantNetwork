import 'dart:async';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';

Future<void> runStaggeredBatches<T>({
  required List<T> items,
  required int maxConcurrent,
  required Duration staggerInterval,
  required Future<void> Function(T item) task,
  Future<void> Function(Duration duration) wait = Future<void>.delayed,
}) async {
  for (final batch in items.batch(maxConcurrent)) {
    await Future.wait(
      batch.indexed.map((entry) async {
        final (index, item) = entry;
        if (index > 0) {
          await wait(staggerInterval * index);
        }
        await task(item);
      }),
    );
  }
}

extension FutureExt<T> on Future<T> {
  Future<T> withTimeout({
    Duration? timeout,
    String? tag,
    VoidCallback? onLast,
    FutureOr<T> Function()? onTimeout,
  }) {
    final realTimeout = timeout ?? const Duration(minutes: 3);
    final cleanupTimer = onLast == null
        ? null
        : Timer(realTimeout + commonDuration, onLast);
    if (cleanupTimer != null) {
      unawaited(
        then<void>(
          (_) => cleanupTimer.cancel(),
          onError: (Object _, StackTrace _) {
            cleanupTimer.cancel();
          },
        ),
      );
    }
    return this.timeout(
      realTimeout,
      onTimeout: () async {
        if (onTimeout != null) {
          return onTimeout();
        } else {
          throw TimeoutException('${tag ?? runtimeType} timeout');
        }
      },
    );
  }
}

extension CompleterExt<T> on Completer<T> {
  void safeCompleter(T value) {
    if (isCompleted) {
      return;
    }
    complete(value);
  }
}
