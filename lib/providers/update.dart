import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/update/platform_update_installer.dart';
import 'package:fl_clash/features/update/update_controller.dart';
import 'package:fl_clash/features/update/update_download.dart';
import 'package:fl_clash/features/update/update_store.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final updateTaskProvider = Provider<UpdateController>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30)));
  final controller = UpdateController(
    store: UpdateStore(
      appPath.dataDir.future.then(
        (directory) => Directory(p.join(directory.path, 'updates')),
      ),
    ),
    downloader: UpdateDownload(dio),
    installer: PlatformUpdateInstaller(),
    version: globalState.packageInfo.version,
    build: int.tryParse(globalState.packageInfo.buildNumber) ?? 0,
    onInstallerLaunched: () async {
      if (!Platform.isAndroid) {
        await ref.read(systemActionProvider.notifier).handleExit(true);
      }
    },
  );
  ref.onDispose(() {
    controller.dispose();
    dio.close(force: true);
  });
  return controller;
});
