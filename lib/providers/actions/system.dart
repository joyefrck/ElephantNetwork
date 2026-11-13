part of '../action.dart';

@Riverpod(keepAlive: true)
class SystemAction extends _$SystemAction {
  SystemExitCoordinator? _exitCoordinator;
  final _proxyModeScheduler = SerialTaskScheduler();
  final _apnsScheduler = SerialTaskScheduler();
  int _proxyModeRevision = 0;
  bool _proxyModeNeedsApply = false;
  Future<void>? _resetSettingsOperation;

  @override
  void build() {}

  Future<List<String>> getChinaPackageNames() async {
    return await app?.getChinaPackageNames() ?? [];
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    return await app?.isInstalledAppsPermissionGranted() ?? true;
  }

  Future<bool> requestInstalledAppsPermission() async {
    return await app?.requestInstalledAppsPermission() ?? false;
  }

  Future<List<Package>> refreshPackages() async {
    final packages = await app?.getPackages();
    if (packages != null) ref.read(packagesProvider.notifier).value = packages;
    return ref.read(packagesProvider);
  }

  Future<List<Package>> getPackages() async {
    if (ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    if (ref.read(packagesProvider).isEmpty) {
      ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return ref.read(packagesProvider);
  }

  Future<void> handleExit([bool needSave = false]) {
    final coordinator = _exitCoordinator ??= SystemExitCoordinator(
      watchdogDuration: exitWatchdogDuration,
      closeWindow: closeWindow,
      closeCore: closeCore,
      exitApplication: exitApplication,
    );
    return coordinator.exit(cleanup: () => cleanupExitResources(needSave));
  }

  @protected
  Duration get exitWatchdogDuration => const Duration(seconds: 3);

  @protected
  Future<void> cleanupExitResources(bool needSave) async {
    if (!dataMutationQueue.isCurrent) await dataMutationQueue.idle;
    await Future.wait([
      if (needSave) preferences.saveConfig(ref.read(configProvider)),
      if (macOS != null) macOS!.updateDns(true),
      if (systemProxyQueue != null) systemProxyQueue!.close(),
      if (tray != null) tray!.destroy(),
    ]);
  }

  @protected
  Future<void> closeWindow() async {
    await window?.close();
  }

  @protected
  Future<void> closeCore() async {
    await coreController.close();
    commonPrint.log('exit');
  }

  @protected
  Future<void> exitApplication() {
    return system.exit();
  }

  Future<void> handleClose([bool exit = true]) async {
    if (ref.read(appSettingProvider).minimizeOnExit || !exit) {
      if (system.isDesktop) {
        await preferences.saveConfig(ref.read(configProvider));
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  Future<void> updateVisible() async {
    final visible = await window?.isVisible;
    if (visible != null && !visible) {
      window?.show();
    } else {
      window?.hide();
    }
  }

  Future<void> selectProxyMode({required bool tun}) {
    final revision = ++_proxyModeRevision;
    return _proxyModeScheduler.run(() async {
      if (!ref.mounted || revision != _proxyModeRevision) return;
      final previousTun = ref.read(patchClashConfigProvider).tun.enable;
      final previousProxy = ref.read(networkSettingProvider).systemProxy;
      if (previousTun == tun && previousProxy != tun && !_proxyModeNeedsApply) {
        return;
      }
      final setup = ref.read(setupActionProvider.notifier);
      try {
        if (tun) await setup.prepareDesktopTun();
        if (!ref.mounted || revision != _proxyModeRevision) return;
        _proxyModeNeedsApply = true;
        await setup.applyDesktopTun(tun);
        if (!ref.mounted) return;
        if (revision != _proxyModeRevision) return;
        _proxyModeNeedsApply = false;
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: tun));
        ref
            .read(networkSettingProvider.notifier)
            .update((state) => state.copyWith(systemProxy: !tun));
      } catch (error) {
        if (!ref.mounted || revision != _proxyModeRevision) return;
        reportProxyModeFailure(error);
      }
    });
  }

  @protected
  void reportProxyModeFailure(Object error) {
    globalState.showNotifier(
      '${currentAppLocalizations.proxyModeSwitchFailed}: $error',
    );
  }

  Future<void> configureApns(NetworkProps settings, {bool enableTun = false}) =>
      _apnsScheduler.run(() async {
        final previousMode = ref.read(patchClashConfigProvider).mode;
        if (enableTun) {
          await selectProxyMode(tun: true);
          if (!ref.read(patchClashConfigProvider).tun.enable) {
            throw StateError(currentAppLocalizations.tunAuthorizationFailed);
          }
          ref
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith(mode: Mode.rule));
        }
        final previous = ref.read(networkSettingProvider);
        ref
            .read(networkSettingProvider.notifier)
            .update(
              (state) => state.copyWith(
                includeApns: settings.includeApns,
                apnsRoute: settings.apnsRoute,
                apnsProxy: settings.apnsProxy,
              ),
            );
        try {
          await applyApnsProfile();
        } catch (_) {
          if (enableTun &&
              ref.read(patchClashConfigProvider).mode == Mode.rule) {
            ref
                .read(patchClashConfigProvider.notifier)
                .update((state) => state.copyWith(mode: previousMode));
          }
          ref
              .read(networkSettingProvider.notifier)
              .update(
                (state) => state.copyWith(
                  includeApns: previous.includeApns,
                  apnsRoute: previous.apnsRoute,
                  apnsProxy: previous.apnsProxy,
                ),
              );
          ref
              .read(setupActionProvider.notifier)
              .applyProfileDebounce(silence: true);
          rethrow;
        }
      });

  @protected
  Future<void> applyApnsProfile() async {
    if (!ref.read(initProvider)) return;
    if (ref.read(currentProfileIdProvider) == null) return;
    await ref.read(setupActionProvider.notifier).applyProfileChecked();
  }

  Future<void> updateTun() => selectProxyMode(tun: true);

  Future<void> updateSystemProxy() => selectProxyMode(tun: false);

  Future<void> restoreDefaultSettings() {
    if (_resetSettingsOperation != null) return _resetSettingsOperation!;
    ++_proxyModeRevision;
    return _resetSettingsOperation = _proxyModeScheduler
        .run(() => dataMutationQueue.run(_restoreDefaultSettings))
        .whenComplete(() => _resetSettingsOperation = null);
  }

  @protected
  Future<bool> persistSettings(Config config) => preferences.saveConfig(config);

  Future<void> _restoreDefaultSettings() async {
    if (!ref.mounted) return;
    final previous = ref.read(configProvider);
    final setup = ref.read(setupActionProvider.notifier);
    if (_proxyModeNeedsApply) {
      await setup.applyDesktopTun(previous.patchClashConfig.tun.enable);
      if (!ref.mounted) return;
      _proxyModeNeedsApply = false;
    }
    final defaults = Config.realFromJson(
      null,
    ).copyWith(currentProfileId: previous.currentProfileId);
    debouncer.cancel(FunctionTag.savePreferences);
    if (!await persistSettings(defaults)) {
      throw StateError(currentAppLocalizations.restoreDefaultsSaveFailed);
    }
    if (!ref.mounted) return;
    final wasRunning = ref.read(isStartProvider);
    try {
      if (wasRunning) await setup.setRunning(false);
    } catch (_) {
      await persistSettings(previous);
      if (ref.mounted && wasRunning) await setup.setRunning(true);
      rethrow;
    }
    if (!ref.mounted) return;
    applyConfigSettings(ref, defaults);
    _proxyModeNeedsApply = false;
  }

  void updateAutoLaunch() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: !state.autoLaunch));
  }

  Future<void> updateTray() async {
    tray?.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
      ),
    );
  }

  Future<void> updateLocalIp() async {
    ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    ref.read(localIpProvider.notifier).value = await utils.getLocalIpAddress();
  }
}
