import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('elephant-lock-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'coalesces acquisition and preserves existing lock-file contents',
    () async {
      final file = File('${root.path}/data.lock');
      await file.writeAsString('retained metadata');
      final lock = SingleInstanceLock.forTesting(() async => file.path);
      addTearDown(lock.release);
      final first = lock.acquire();
      final second = lock.acquire();
      expect(identical(first, second), isTrue);
      expect(await first, isTrue);
      expect(await file.readAsString(), 'retained metadata');
      expect(await lock.acquire(), isTrue);
    },
  );

  test('a second process cannot acquire the active data lock', () async {
    final path = '${root.path}/data.lock';
    final script = File('${root.path}/holder.dart');
    await script.writeAsString(
      "import 'dart:io'; Future<void> main(List<String> args) async {final file=await File(args.single).open(mode:FileMode.append);await file.lock();stdout.writeln('locked');await stdout.flush();stdin.readLineSync();await file.close();}",
    );
    final process = await Process.start('dart', [script.path, path]);
    final ready = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    expect(ready, 'locked');
    final lock = SingleInstanceLock.forTesting(() async => path);
    addTearDown(lock.release);
    try {
      expect(await lock.acquire(), isFalse);
    } finally {
      process.stdin.writeln('release');
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 10));
    }
    expect(await lock.acquire(), isTrue);
  });

  test(
    'filesystem failures surface instead of looking like another instance',
    () async {
      final parent = File('${root.path}/not-a-directory');
      await parent.writeAsString('retained');
      final lock = SingleInstanceLock.forTesting(
        () async => '${parent.path}/data.lock',
      );
      await expectLater(lock.acquire(), throwsA(isA<FileSystemException>()));
      expect(await parent.readAsString(), 'retained');
    },
  );
}
