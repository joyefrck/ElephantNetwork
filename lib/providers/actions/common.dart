part of '../action.dart';

@Riverpod(keepAlive: true)
AppUpdateClient appUpdateClient(Ref ref) {
  return AppUpdateClient(
    dio: request.dio,
    resolveBaseUrl: xboardDomainResolver.resolve,
  );
}

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  Future<void>? _pendingUpdateCheck;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    ref
        .read(setupActionProvider.notifier)
        .setRunning(running, initialize: running && !ref.read(initProvider));
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    final onlyStatisticsProxy = ref.read(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    try {
      final traffic = await coreController.getTraffic(onlyStatisticsProxy);
      ref.read(trafficsProvider.notifier).addTraffic(traffic);
      ref.read(totalTrafficProvider.notifier).value = await coreController
          .getTotalTraffic(onlyStatisticsProxy);
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<void> autoCheckUpdate() => _checkUpdate(isUser: false);

  Future<void> checkUpdate() => _checkUpdate(isUser: true);

  Future<void> _checkUpdate({required bool isUser}) {
    return _pendingUpdateCheck ??= _fetchUpdate(isUser: isUser).whenComplete(
      () {
        _pendingUpdateCheck = null;
      },
    );
  }

  Future<void> _fetchUpdate({required bool isUser}) async {
    try {
      final task = ref.read(updateTaskProvider);
      await task.recover();
      if (!ref.mounted) return;
      if (task.value.busy) {
        await _showUpdateDialog();
        return;
      }
      final data = await ref
          .read(appUpdateClientProvider)
          .check(
            version: globalState.packageInfo.version,
            build: globalState.packageInfo.buildNumber,
          );
      if (!ref.mounted) return;
      if (data == null && task.canInstall) {
        await _showUpdateDialog();
      } else {
        await checkUpdateResultHandle(data: data, isUser: isUser);
      }
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: $error',
        logLevel: LogLevel.warning,
      );
      if (isUser &&
          ref.mounted &&
          globalState.navigatorKey.currentContext?.mounted == true) {
        await globalState.showMessage(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(
            text: error is FormatException
                ? currentAppLocalizations.updateFailed
                : currentAppLocalizations.networkException,
          ),
        );
      }
    }
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (data != null) {
      final task = ref.read(updateTaskProvider);
      await task.offer(UpdateRelease.fromJson(data));
      if (!ref.mounted) return;
      await _showUpdateDialog();
    } else if (isUser) {
      await globalState.showMessage(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: currentAppLocalizations.checkUpdateError),
      );
    }
  }

  Future<void> _showUpdateDialog() async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDownloadDialog(),
    );
  }
}
