import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'update_download.dart';
import 'update_installer.dart';
import 'update_release.dart';
import 'update_store.dart';

enum UpdatePhase {
  available,
  downloading,
  verifying,
  ready,
  installing,
  authorizationRequired,
  failed,
  cancelled,
  installed,
}

final class UpdateSnapshot {
  const UpdateSnapshot({
    this.release,
    this.phase = UpdatePhase.available,
    this.received = 0,
    this.error,
  });

  final UpdateRelease? release;
  final UpdatePhase phase;
  final int received;
  final Object? error;

  bool get busy => const {
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(phase);
}

class UpdateController extends ValueNotifier<UpdateSnapshot> {
  UpdateController({
    required this.store,
    required this.downloader,
    required this.installer,
    required this.version,
    required this.build,
    this.platform,
    this.arch,
    this.onInstallerLaunched,
  }) : super(const UpdateSnapshot());

  final UpdateStore store;
  final UpdateDownload downloader;
  final UpdateInstaller installer;
  final String version;
  final int build;
  final String? platform;
  final String? arch;
  final Future<void> Function()? onInstallerLaunched;
  Future<void>? _operation;
  Future<void>? _recovery;
  CancelToken? _cancelToken;
  UpdateTask? _task;
  bool _disposed = false;

  void _set(UpdateSnapshot snapshot) {
    if (!_disposed) value = snapshot;
  }

  Future<void> recover() => _recovery ??= _recover();

  Future<void> _recover() async {
    final task = await store.recover();
    if (_disposed || task == null) return;
    try {
      task.release.validateTarget(platform: platform, arch: arch);
      if (!task.release.isNewerThan(version, build)) {
        await store.discard(task);
        return;
      }
      _task = task;
      final status = await installer.recover(task);
      _set(
        UpdateSnapshot(
          release: task.release,
          phase: switch (status) {
            UpdateInstallResult.installed => UpdatePhase.installed,
            UpdateInstallResult.launched => UpdatePhase.installing,
            _ => UpdatePhase.ready,
          },
        ),
      );
    } on Object catch (error) {
      _set(
        UpdateSnapshot(
          release: task.release,
          phase: UpdatePhase.failed,
          error: error,
        ),
      );
    }
  }

  Future<void> offer(UpdateRelease release) async {
    await recover();
    release.validateTarget(platform: platform, arch: arch);
    if (!release.isNewerThan(version, build)) {
      throw const FormatException(
        'Update is not newer than the installed application',
      );
    }
    if (value.busy) return;
    if (value.release?.sha256 == release.sha256 && _task != null) return;
    final previous = _task;
    if (previous != null) await store.discard(previous);
    _task = null;
    _set(UpdateSnapshot(release: release));
  }

  Future<void> download() {
    return _operation ??= _download().whenComplete(() => _operation = null);
  }

  Future<void> _download() async {
    final release = value.release;
    if (release == null || _disposed || value.busy) return;
    final token = CancelToken();
    _cancelToken = token;
    _set(UpdateSnapshot(release: release, phase: UpdatePhase.downloading));
    UpdateTask? task;
    try {
      final previous = _task;
      if (previous != null) await store.discard(previous);
      _task = null;
      task = await store.create(release);
      final part = await downloader.download(
        task,
        cancelToken: token,
        onProgress: (received) {
          if (token.isCancelled) return;
          _set(
            UpdateSnapshot(
              release: release,
              phase: UpdatePhase.downloading,
              received: received,
            ),
          );
        },
      );
      token.checkUpdateCancellation();
      _set(UpdateSnapshot(release: release, phase: UpdatePhase.verifying));
      await store.verify(task, file: part);
      token.checkUpdateCancellation();
      await part.rename(task.file.path);
      await store.save(task);
      token.checkUpdateCancellation();
      _task = task;
      _set(UpdateSnapshot(release: release, phase: UpdatePhase.ready));
    } on Object catch (error) {
      if (task != null) await store.discard(task);
      _set(
        UpdateSnapshot(
          release: release,
          phase: token.isCancelled ? UpdatePhase.cancelled : UpdatePhase.failed,
          error: token.isCancelled ? null : error,
        ),
      );
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel('Update cancelled');

  Future<void> install() {
    return _operation ??= _install().whenComplete(() => _operation = null);
  }

  Future<void> _install() async {
    final task = _task;
    if (task == null || _disposed || value.busy) return;
    _set(UpdateSnapshot(release: task.release, phase: UpdatePhase.installing));
    var artifactVerified = false;
    try {
      await store.verify(task);
      artifactVerified = true;
      await installer.prepare(task);
      final result = await installer.install(task);
      _set(
        UpdateSnapshot(
          release: task.release,
          phase: switch (result) {
            UpdateInstallResult.authorizationRequired =>
              UpdatePhase.authorizationRequired,
            UpdateInstallResult.cancelled => UpdatePhase.ready,
            UpdateInstallResult.installed => UpdatePhase.installed,
            UpdateInstallResult.launched => UpdatePhase.installing,
          },
        ),
      );
      if (result == UpdateInstallResult.launched) {
        await onInstallerLaunched?.call();
      }
    } on Object catch (error) {
      if (!artifactVerified) {
        await store.discard(task);
        _task = null;
      }
      _set(
        UpdateSnapshot(
          release: task.release,
          phase: UpdatePhase.failed,
          error: error,
        ),
      );
    }
  }

  Future<void> refreshInstall() async {
    final task = _task;
    if (task == null || value.phase != UpdatePhase.installing) return;
    try {
      final result = await installer.recover(task);
      if (result == UpdateInstallResult.cancelled ||
          result == UpdateInstallResult.installed) {
        _set(
          UpdateSnapshot(
            release: task.release,
            phase: result == UpdateInstallResult.installed
                ? UpdatePhase.installed
                : UpdatePhase.ready,
          ),
        );
      }
    } on Object catch (error) {
      _set(
        UpdateSnapshot(
          release: task.release,
          phase: UpdatePhase.failed,
          error: error,
        ),
      );
    }
  }

  bool get canInstall => _task != null && !value.busy;

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
