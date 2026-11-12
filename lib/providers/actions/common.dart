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
      final data = await ref
          .read(appUpdateClientProvider)
          .check(
            version: globalState.packageInfo.version,
            build: globalState.packageInfo.buildNumber,
          );
      if (!ref.mounted) return;
      await checkUpdateResultHandle(data: data, isUser: isUser);
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
          message: TextSpan(text: currentAppLocalizations.networkException),
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
      final tagName = data['tag_name']?.toString() ?? '';
      final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final build = data['build_number']?.toString() ?? '';
      final body = data['body']?.toString().trim() ?? '';
      final l10n = context.appLocalizations;
      final textTheme = context.textTheme;
      final res = await globalState.showMessage(
        title: l10n.discoverNewVersion,
        message: TextSpan(
          text: '${l10n.versionWithBuild(version, build)}\n\n',
          style: textTheme.headlineSmall,
          children: [
            TextSpan(
              text: '${l10n.releaseNotes}\n',
              style: textTheme.titleSmall,
            ),
            TextSpan(
              text: body.isEmpty ? l10n.releaseNotesUnavailable : body,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
        confirmText: l10n.update,
        cancelText: l10n.cancel,
      );
      if (res == true) {
        final downloadUri = Uri.tryParse(
          data['download_url']?.toString() ?? '',
        );
        if (downloadUri != null && downloadUri.scheme == 'https') {
          await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
        }
      }
    } else if (isUser) {
      await globalState.showMessage(
        title: currentAppLocalizations.checkUpdate,
        message: TextSpan(text: currentAppLocalizations.checkUpdateError),
      );
    }
  }
}
