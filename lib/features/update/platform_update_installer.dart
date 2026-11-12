import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'update_installer.dart';
import 'update_store.dart';

class PlatformUpdateInstaller implements UpdateInstaller {
  static const _channel = MethodChannel('com.elephantroute/app');

  Map<String, Object> _arguments(UpdateTask task) => {
    'id': task.id,
    'path': task.file.path,
    'size': task.release.size,
    'sha256': task.release.sha256,
    'build': task.release.build,
    'version': task.release.version,
    'arch': task.release.arch,
  };

  String get _helper =>
      p.join(p.dirname(Platform.resolvedExecutable), 'ElephantNetworkUpdater');
  File _manifest(UpdateTask task) =>
      File(p.join(task.file.parent.path, 'install.json'));
  File _status(UpdateTask task) =>
      File(p.join(task.file.parent.path, 'install-state.json'));

  Future<ProcessResult> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return result;
  }

  @override
  Future<void> prepare(UpdateTask task) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<String>('prepareUpdate', _arguments(task));
      return;
    }
    if (Platform.isWindows) {
      await _prepareWindows(task);
      return;
    }
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('Unsupported update platform');
    }
    final uid = int.parse(
      '${(await _run('/usr/bin/id', ['-u'])).stdout}'.trim(),
    );
    final executable = File(Platform.resolvedExecutable).absolute.path;
    final application = Platform.isMacOS
        ? p.dirname(p.dirname(p.dirname(executable)))
        : executable;
    await _manifest(task).writeAsString(
      jsonEncode({
        'id': task.id,
        'file': task.file.path,
        'app': application,
        'pid': pid,
        'uid': uid,
        'release': task.release.toJson(),
      }),
      flush: true,
    );
    final helper = await File(
      _helper,
    ).copy(p.join(task.file.parent.path, 'ElephantNetworkUpdater'));
    await _run('/bin/chmod', ['700', helper.path]);
    await _run(helper.path, ['--prepare', _manifest(task).path]);
  }

  Future<void> _prepareWindows(UpdateTask task) async {
    const script = r'''
$ErrorActionPreference = 'Stop'
$source = Get-AuthenticodeSignature -LiteralPath $env:ELEPHANT_CURRENT_EXE
$target = Get-AuthenticodeSignature -LiteralPath $env:ELEPHANT_UPDATE_EXE
if ($source.Status -eq 'Valid') {
  if ($target.Status -ne 'Valid' -or $source.SignerCertificate.Thumbprint -ne $target.SignerCertificate.Thumbprint) { throw 'Installer publisher mismatch' }
}
$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($env:ELEPHANT_UPDATE_EXE)
if ($info.ProductName -ne 'Elephant Network' -and $info.ProductName -ne 'ElephantNetwork') { throw 'Installer product mismatch' }
if ($info.FileDescription -ne ('Elephant Network Installer (' + $env:ELEPHANT_UPDATE_ARCH + ')')) { throw 'Installer architecture mismatch' }
$expected = [version]$env:ELEPHANT_UPDATE_VERSION
if ($info.FileMajorPart -ne $expected.Major -or $info.FileMinorPart -ne $expected.Minor -or $info.FileBuildPart -ne $expected.Build -or $info.FilePrivatePart -ne [int]$env:ELEPHANT_UPDATE_BUILD) { throw 'Installer version mismatch' }
$locations = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245}_is1', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245}_is1')
$installed = $false
foreach ($key in $locations) {
  $record = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
  if ($record -and $record.InstallLocation.TrimEnd('\') -eq [IO.Path]::GetDirectoryName($env:ELEPHANT_CURRENT_EXE)) { $installed = $true }
}
if (-not $installed) { throw 'Install the official application before using in-app updates' }

''';
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: {
        'ELEPHANT_CURRENT_EXE': Platform.resolvedExecutable,
        'ELEPHANT_UPDATE_EXE': task.file.path,
        'ELEPHANT_UPDATE_VERSION': task.release.version,
        'ELEPHANT_UPDATE_BUILD': '${task.release.build}',
        'ELEPHANT_UPDATE_ARCH': task.release.arch,
      },
    );
    if (result.exitCode != 0) throw StateError('${result.stderr}');
  }

  @override
  Future<UpdateInstallResult> install(UpdateTask task) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<String>(
        'installUpdate',
        _arguments(task),
      );
      return UpdateInstallResult.values.firstWhere(
        (value) => value.name == result,
      );
    }
    if (Platform.isWindows) {
      final status = _status(task);
      if (await status.exists()) await status.delete();
      final process = await Process.start(task.file.path, [
        '/INAPPUPDATE=1',
        '/UPDATEPID=$pid',
        '/UPDATETASK=${task.id}',
        '/DIR=${p.dirname(Platform.resolvedExecutable)}',
        '/SILENT',
        '/NOICONS',
      ]);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      var exited = false;
      unawaited(process.exitCode.then((_) => exited = true));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        if (await status.exists()) {
          final data = jsonDecode(await status.readAsString()) as Map;
          if (data['state'] == 'waitingForExit') {
            return UpdateInstallResult.launched;
          }
        }
        if (exited) return UpdateInstallResult.cancelled;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      throw StateError('Installer authorization timed out');
    }
    final status = _status(task);
    if (await status.exists()) await status.delete();
    await Process.start(
      p.join(task.file.parent.path, 'ElephantNetworkUpdater'),
      ['--install', _manifest(task).path],
      mode: ProcessStartMode.detached,
    );
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (await status.exists()) {
        final data = jsonDecode(await status.readAsString()) as Map;
        if (data['state'] == 'waitingForExit') {
          return UpdateInstallResult.launched;
        }
        if (data['state'] == 'failed') {
          throw StateError(data['error']?.toString() ?? 'Installation failed');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Installer did not become ready');
  }

  @override
  Future<UpdateInstallResult?> recover(UpdateTask task) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<String>('recoverUpdate', {
        'id': task.id,
      });
      if (result == 'failed') {
        throw StateError('System installer rejected the update');
      }
      return switch (result) {
        'installed' => UpdateInstallResult.installed,
        'cancelled' => UpdateInstallResult.cancelled,
        'installing' => UpdateInstallResult.launched,
        _ => null,
      };
    }
    final status = _status(task);
    if (!await status.exists()) return null;
    final data = jsonDecode(await status.readAsString()) as Map;
    if (data['state'] == 'failed') {
      throw StateError(data['error']?.toString() ?? 'Installation failed');
    }
    return switch (data['state']) {
      'installed' => UpdateInstallResult.installed,
      _ => null,
    };
  }
}
