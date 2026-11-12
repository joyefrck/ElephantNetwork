import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/update_controller.dart';
import 'package:fl_clash/features/update/update_download.dart';
import 'package:fl_clash/features/update/update_installer.dart';
import 'package:fl_clash/features/update/update_release.dart';
import 'package:fl_clash/features/update/update_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late UpdateStore store;
  late Dio dio;
  late _Installer installer;
  late _Adapter adapter;
  final bytes = utf8.encode('private test installer');

  UpdateRelease release({Map<String, dynamic> fields = const {}}) =>
      UpdateRelease.fromJson({
        'version': '2.1.0',
        'build_number': 22102,
        'platform': 'macos',
        'arch': 'arm64',
        'download_url': 'https://updates.example/client.dmg',
        'file_size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        ...fields,
      });

  UpdateController controller() => UpdateController(
    store: store,
    downloader: UpdateDownload(dio),
    installer: installer,
    version: '2.1.0',
    build: 22101,
    platform: 'macos',
    arch: 'arm64',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elephant-update-test-');
    store = UpdateStore(Future.value(root));
    adapter = _Adapter((_) async => ResponseBody.fromBytes(bytes, 200));
    dio = Dio()..httpClientAdapter = adapter;
    installer = _Installer();
  });
  tearDown(() async {
    dio.close(force: true);
    await root.delete(recursive: true);
  });

  test(
    'metadata rejects missing hash, missing size and wrong architecture',
    () {
      expect(() => release(fields: {'sha256': ''}), throwsFormatException);
      expect(() => release(fields: {'file_size': null}), throwsFormatException);
      expect(
        () => release(fields: {'download_url': 'http://updates.example/app'}),
        throwsFormatException,
      );
      expect(
        () => release().validateTarget(platform: 'macos', arch: 'x64'),
        throwsFormatException,
      );
      expect(
        () => release().validateTarget(platform: 'windows', arch: 'arm64'),
        throwsFormatException,
      );
      expect(UpdateRelease.normalizeArch('aarch64'), 'arm64');
    },
  );

  test(
    'artifacts use canonical paths for native installer validation',
    () async {
      final task = await store.create(release());
      expect(
        task.file.path,
        startsWith('${await root.resolveSymbolicLinks()}/'),
      );
    },
  );

  test(
    'same version with newer build downloads, verifies and recovers',
    () async {
      final task = controller();
      addTearDown(task.dispose);
      await task.offer(release());
      final first = task.download();
      final second = task.download();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(adapter.calls, 1);
      expect(task.value.phase, UpdatePhase.ready);
      expect(task.value.error, isNull);
      expect((await store.recover())?.release.build, 22102);
      final restored = controller();
      addTearDown(restored.dispose);
      await restored.recover();
      expect(restored.value.phase, UpdatePhase.ready);
      await restored.install();
      expect(installer.prepared, 1);
      expect(installer.installs, 1);
      expect(restored.value.phase, UpdatePhase.ready);
    },
  );

  test('installer failure retains a verified package for retry', () async {
    final task = controller();
    addTearDown(task.dispose);
    await task.offer(release());
    await task.download();
    installer.error = StateError('authorization denied');
    await task.install();
    expect(task.value.phase, UpdatePhase.failed);
    expect(task.canInstall, isTrue);
    expect(await store.recover(), isNotNull);
    installer.error = null;
    await task.install();
    expect(task.value.phase, UpdatePhase.ready);
  });

  test(
    'resuming an unsuccessful system installation shows a retryable error',
    () async {
      final task = controller();
      addTearDown(task.dispose);
      await task.offer(release());
      await task.download();
      installer.result = UpdateInstallResult.launched;
      await task.install();
      installer.recoveryError = StateError('system installation failed');
      await task.refreshInstall();
      expect(task.value.phase, UpdatePhase.failed);
      expect(task.canInstall, isTrue);
    },
  );

  test('older versions and builds cannot become update tasks', () async {
    final task = controller();
    addTearDown(task.dispose);
    await expectLater(
      task.offer(release(fields: {'version': '2.0.9'})),
      throwsFormatException,
    );
    await expectLater(
      task.offer(release(fields: {'build_number': 22101})),
      throwsFormatException,
    );
    expect(
      release(fields: {'version': '2.1.1'}).isNewerThan('2.1.0', 22101),
      isTrue,
    );
  });

  test('bad checksum leaves no installable task and permits retry', () async {
    adapter.response = (_) async =>
        ResponseBody.fromBytes(List.filled(bytes.length, 0), 200);
    final task = controller();
    addTearDown(task.dispose);
    await task.offer(release());
    await task.download();
    expect(task.value.phase, UpdatePhase.failed);
    expect(task.canInstall, isFalse);
    expect(await store.recover(), isNull);
    expect(await root.list().toList(), isEmpty);
    adapter.response = (_) async => ResponseBody.fromBytes(bytes, 200);
    await task.download();
    expect(task.value.phase, UpdatePhase.ready);
  });

  test('rejects size mismatch and truncated response', () async {
    for (final response in [
      ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          'content-length': ['9999'],
        },
      ),
      ResponseBody.fromBytes(bytes.sublist(1), 200),
      ResponseBody.fromBytes([...bytes, 0], 200),
    ]) {
      adapter.response = (_) async => response;
      final task = controller();
      await task.offer(release());
      await task.download();
      expect(task.value.phase, UpdatePhase.failed);
      expect(task.canInstall, isFalse);
      task.dispose();
    }
  });

  test('HTTPS redirect succeeds, downgrade and redirect loop fail', () async {
    final task = controller();
    addTearDown(task.dispose);
    await task.offer(release());
    adapter.response = (options) async => options.uri.path == '/client.dmg'
        ? ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['/verified.dmg'],
            },
          )
        : ResponseBody.fromBytes(bytes, 200);
    await task.download();
    expect(task.value.phase, UpdatePhase.ready);
    adapter.response = (_) async => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['http://bad.example/file'],
      },
    );
    await task.download();
    expect(task.value.phase, UpdatePhase.failed);
    expect(adapter.calls, 3);
    adapter.response = (_) async => ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['/loop'],
      },
    );
    await task.download();
    expect(task.value.phase, UpdatePhase.failed);
  });

  test(
    'offline error and cancellation clean partial data and allow retry',
    () async {
      final task = controller();
      addTearDown(task.dispose);
      await task.offer(release());
      adapter.response = (_) async => throw const SocketException('offline');
      await task.download();
      expect(task.value.phase, UpdatePhase.failed);
      final stream = StreamController<Uint8List>();
      adapter.response = (_) async => ResponseBody(stream.stream, 200);
      final pending = task.download();
      while (!await root
          .list(recursive: true)
          .any((entry) => entry.path.endsWith('.part'))) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      task.cancel();
      stream.add(Uint8List.fromList(bytes));
      await stream.close();
      await pending;
      expect(task.value.phase, UpdatePhase.cancelled);
      expect(await root.list().toList(), isEmpty);
      adapter.response = (_) async => ResponseBody.fromBytes(bytes, 200);
      await task.download();
      expect(task.value.phase, UpdatePhase.ready);
    },
  );

  test('recovery and installation recheck file contents', () async {
    final task = controller();
    addTearDown(task.dispose);
    await task.offer(release());
    await task.download();
    final saved = (await store.recover())!;
    await saved.file.writeAsBytes(List.filled(bytes.length, 0));
    await task.install();
    expect(installer.prepared, 0);
    expect(installer.installs, 0);
    expect(task.value.phase, UpdatePhase.failed);
    expect(await store.recover(), isNull);
  });

  test(
    'pending manifest cannot escape the task directory or follow a symlink',
    () async {
      final task = await store.create(release());
      await task.file.writeAsBytes(bytes);
      await store.save(task);
      final manifest = File('${root.path}/pending.json');
      final data = jsonDecode(await manifest.readAsString()) as Map;
      data['id'] = '../../elsewhere';
      await manifest.writeAsString(jsonEncode(data));
      expect(await store.recover(), isNull);
      await task.file.delete();
      final outside = File('${root.path}/elsewhere');
      await outside.writeAsBytes(bytes);
      await Link(task.file.path).create(outside.path);
      await expectLater(store.save(task), throwsFormatException);
      expect(await outside.readAsBytes(), bytes);
    },
  );

  test(
    'installed build retires pending task without deleting user data',
    () async {
      final original = controller();
      addTearDown(original.dispose);
      await original.offer(release());
      await original.download();
      final account = File('${root.path}/account.json');
      await account.writeAsString('retained');
      final updated = UpdateController(
        store: store,
        downloader: UpdateDownload(dio),
        installer: installer,
        version: '2.1.0',
        build: 22102,
        platform: 'macos',
        arch: 'arm64',
      );
      addTearDown(updated.dispose);
      await updated.recover();
      expect(updated.value.release, isNull);
      expect(await store.recover(), isNull);
      expect(await account.readAsString(), 'retained');
    },
  );
}

class _Installer implements UpdateInstaller {
  Object? error;
  Object? recoveryError;
  UpdateInstallResult result = UpdateInstallResult.cancelled;
  int prepared = 0;
  int installs = 0;
  @override
  Future<void> prepare(UpdateTask task) async => prepared++;
  @override
  Future<UpdateInstallResult> install(UpdateTask task) async {
    installs++;
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<UpdateInstallResult?> recover(UpdateTask task) async {
    if (recoveryError != null) throw recoveryError!;
    return null;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.response);
  Future<ResponseBody> Function(RequestOptions) response;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return response(options);
  }

  @override
  void close({bool force = false}) {}
}
