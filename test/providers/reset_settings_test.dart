import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));

  const previous = Config(
    currentProfileId: 7,
    themeProps: ThemeProps(themeMode: ThemeMode.dark),
    appSettingProps: AppSettingProps(locale: 'zh_CN', autoRun: true),
    networkProps: NetworkProps(
      systemProxy: false,
      bypassDomain: ['example.org'],
    ),
    patchClashConfig: PatchClashConfig(
      tun: Tun(enable: true),
      mixedPort: 12345,
    ),
    vpnProps: VpnProps(enable: false),
    windowProps: WindowProps(width: 1200, height: 800),
    proxiesStyleProps: ProxiesStyleProps(sortType: ProxiesSortType.name),
    davProps: DAVProps(uri: 'https://example.org', user: 'test'),
    overrideDns: true,
    hotKeyActions: [HotKeyAction(action: HotAction.tun)],
    excludeSSIDs: ['example'],
  );
  const profile = Profile(
    id: 7,
    label: 'Subscription',
    autoUpdateDuration: Duration.zero,
  );
  late ProviderContainer container;
  late _ResetSystem action;
  late _ResetSetup setup;

  setUp(() {
    action = _ResetSystem();
    setup = _ResetSetup();
    container = ProviderContainer(
      overrides: [
        ...buildConfigOverrides(previous),
        profilesProvider.overrideWith(() => _Profiles()),
        systemActionProvider.overrideWith(() => action),
        setupActionProvider.overrideWith(() => setup),
      ],
    );
    container.listen(configProvider, (_, _) {}, fireImmediately: true);
    container.read(systemActionProvider);
  });
  tearDown(() => container.dispose());

  test(
    'resets every setting while preserving subscriptions and selection',
    () async {
      final profiles = container.read(profilesProvider);
      container.read(runTimeProvider.notifier).value = 100;
      await action.restoreDefaultSettings();
      final expected = Config.realFromJson(null).copyWith(currentProfileId: 7);
      expect(container.read(configProvider), expected);
      expect(action.saved, [expected]);
      expect(setup.transitions, [false]);
      expect(container.read(profilesProvider), profiles);
      expect(container.read(profilesProvider).single, profile);
      expect(container.read(isStartProvider), isFalse);
    },
  );

  test(
    'save failure leaves settings and the running state unchanged',
    () async {
      action.saveResult = false;
      container.read(runTimeProvider.notifier).value = 100;
      await expectLater(action.restoreDefaultSettings(), throwsStateError);
      expect(container.read(configProvider), previous);
      expect(container.read(isStartProvider), isTrue);
      expect(setup.transitions, isEmpty);
    },
  );

  test('stop failure restores persisted settings and permits retry', () async {
    setup.stopFailure = StateError('stop failed');
    container.read(runTimeProvider.notifier).value = 100;
    await expectLater(action.restoreDefaultSettings(), throwsStateError);
    expect(container.read(configProvider), previous);
    expect(action.saved.last, previous);
    expect(setup.transitions, [false, true]);
    setup.stopFailure = null;
    await action.restoreDefaultSettings();
    expect(
      container.read(configProvider),
      Config.realFromJson(null).copyWith(currentProfileId: 7),
    );
  });

  test('reset supersedes an in-flight proxy mode change', () async {
    setup.applying = Completer<void>();
    final switching = action.updateSystemProxy();
    await Future<void>.delayed(Duration.zero);
    final resetting = action.restoreDefaultSettings();
    setup.applying!.complete();
    await Future.wait([switching, resetting]);
    expect(
      container.read(configProvider),
      Config.realFromJson(null).copyWith(currentProfileId: 7),
    );
  });

  test('failed reset reconciles a superseded runtime mode', () async {
    setup.applying = Completer<void>();
    final switching = action.updateSystemProxy();
    await Future<void>.delayed(Duration.zero);
    action.saveResult = false;
    final resetting = action.restoreDefaultSettings();
    final failure = expectLater(resetting, throwsStateError);
    setup.applying!.complete();
    await switching;
    await failure;
    expect(setup.applied, [false, true]);
    expect(container.read(configProvider), previous);
  });

  test('coalesces repeated resets during persistence', () async {
    action.saving = Completer<void>();
    final first = action.restoreDefaultSettings();
    final second = action.restoreDefaultSettings();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(action.saved, hasLength(1));
    action.saving!.complete();
    await Future.wait([first, second]);
    expect(action.saved, hasLength(1));
  });
}

class _Profiles extends Profiles {
  @override
  List<Profile> build() => [
    const Profile(
      id: 7,
      label: 'Subscription',
      autoUpdateDuration: Duration.zero,
    ),
  ];
}

class _ResetSystem extends SystemAction {
  final saved = <Config>[];
  bool saveResult = true;
  Completer<void>? saving;

  @override
  Future<bool> persistSettings(Config config) async {
    saved.add(config);
    await saving?.future;
    return saveResult;
  }
}

class _ResetSetup extends SetupAction {
  final transitions = <bool>[];
  Object? stopFailure;
  Completer<void>? applying;
  final applied = <bool>[];

  @override
  Future<void> applyDesktopTun(bool enable) async {
    applied.add(enable);
    await applying?.future;
  }

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    transitions.add(running);
    if (!running && stopFailure != null) throw stopFailure!;
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
  }
}
