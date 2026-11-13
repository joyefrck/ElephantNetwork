import 'dart:async';

import 'package:fl_clash/common/desktop_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));
  late ProviderContainer container;
  late _TestSetup setup;
  late _TestSystem action;

  setUp(() {
    setup = _TestSetup();
    action = _TestSystem();
    container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(() => setup),
        systemActionProvider.overrideWith(() => action),
      ],
    );
    container.listen(configProvider, (_, _) {}, fireImmediately: true);
    container.read(systemActionProvider);
  });
  tearDown(() => container.dispose());

  void expectMode(bool tun) {
    expect(container.read(patchClashConfigProvider).tun.enable, tun);
    expect(container.read(networkSettingProvider).systemProxy, !tun);
  }

  test('defaults to system proxy and keeps the selected switch on', () async {
    expectMode(false);
    await action.updateSystemProxy();
    expectMode(false);
    expect(setup.applied, isEmpty);
  });

  for (final tun in [false, true]) {
    for (final proxy in [false, true]) {
      test('normalizes saved settings tun=$tun proxy=$proxy', () {
        final original = Config(
          themeProps: const ThemeProps(),
          patchClashConfig: PatchClashConfig(tun: Tun(enable: tun)),
          networkProps: NetworkProps(systemProxy: proxy),
        );
        final normalized = normalizeDesktopProxyConfig(original);
        final expectedTun = tun != proxy && tun;
        expect(normalized.patchClashConfig.tun.enable, expectedTun);
        expect(normalized.networkProps.systemProxy, !expectedTun);
        final restored = ProviderContainer(
          overrides: buildConfigOverrides(original),
        );
        addTearDown(restored.dispose);
        expect(restored.read(patchClashConfigProvider).tun.enable, expectedTun);
        expect(restored.read(networkSettingProvider).systemProxy, !expectedTun);
      });
    }
  }

  test('switches both settings only after TUN preparation and apply', () async {
    setup.authorization = Completer<void>();
    final operation = action.updateTun();
    await Future<void>.delayed(Duration.zero);
    expectMode(false);
    expect(setup.applied, isEmpty);
    setup.authorization!.complete();
    await operation;
    expectMode(true);
    expect(setup.applied, [true]);
    await action.updateTun();
    expectMode(true);
    expect(setup.applied, [true]);
    await action.updateSystemProxy();
    expectMode(false);
    expect(setup.applied, [true, false]);
  });

  test(
    'authorization failure retains system proxy and reports the error',
    () async {
      setup.authorizationFailure = StateError('cancelled');
      await action.updateTun();
      expectMode(false);
      expect(setup.applied, isEmpty);
      expect(action.errors, [setup.authorizationFailure]);
    },
  );

  test('runtime failure retains the previous mode and permits retry', () async {
    setup.applyFailure = StateError('TUN unavailable');
    await action.updateTun();
    expectMode(false);
    expect(action.errors, [setup.applyFailure]);
    setup.applyFailure = null;
    await action.updateTun();
    expectMode(true);
  });

  test('failed TUN shutdown retains the selected TUN mode', () async {
    await action.updateTun();
    setup.applyFailure = StateError('Core disconnected');
    await action.updateSystemProxy();
    expectMode(true);
    expect(action.errors, [setup.applyFailure]);
  });

  test('new system proxy intent cancels pending authorization', () async {
    setup.authorization = Completer<void>();
    final first = action.updateTun();
    await Future<void>.delayed(Duration.zero);
    final second = action.updateSystemProxy();
    setup.authorization!.complete();
    await Future.wait([first, second]);
    expectMode(false);
    expect(setup.applied, isEmpty);
  });

  test('new intent during apply restores the latest selected mode', () async {
    setup.applying = Completer<void>();
    final first = action.updateTun();
    await Future<void>.delayed(Duration.zero);
    expect(setup.applied, [true]);
    final second = action.updateSystemProxy();
    setup.applying!.complete();
    await Future.wait([first, second]);
    expectMode(false);
    expect(setup.applied, [true, false]);
  });

  test('rapid queued requests apply only the newest intent', () async {
    await Future.wait([
      action.updateTun(),
      action.updateSystemProxy(),
      action.updateTun(),
    ]);
    expectMode(true);
    expect(setup.applied, [true]);
  });

  test(
    'denied native authorization restores system proxy and can be retried',
    () async {
      final nativeSetup = _AuthorizationSetup();
      final scoped = ProviderContainer(
        overrides: [setupActionProvider.overrideWith(() => nativeSetup)],
      );
      addTearDown(scoped.dispose);
      scoped.listen(configProvider, (_, _) {}, fireImmediately: true);
      scoped.read(setupActionProvider);
      scoped
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      scoped
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(systemProxy: false));
      await expectLater(nativeSetup.prepareDesktopTun(), throwsStateError);
      expect(scoped.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(scoped.read(networkSettingProvider).systemProxy, isTrue);
      await expectLater(nativeSetup.prepareDesktopTun(), throwsStateError);
      expect(nativeSetup.requests, 2);
    },
  );
}

class _TestSetup extends SetupAction {
  Completer<void>? authorization;
  Completer<void>? applying;
  Object? authorizationFailure;
  Object? applyFailure;
  final applied = <bool>[];

  @override
  Future<void> prepareDesktopTun() async {
    await authorization?.future;
    if (authorizationFailure != null) throw authorizationFailure!;
  }

  @override
  Future<void> applyDesktopTun(bool enable) async {
    applied.add(enable);
    await applying?.future;
    if (applyFailure != null) throw applyFailure!;
  }
}

class _TestSystem extends SystemAction {
  final errors = <Object>[];

  @override
  void reportProxyModeFailure(Object error) => errors.add(error);
}

class _AuthorizationSetup extends SetupAction {
  int requests = 0;

  @override
  Future<AuthorizeCode> authorizeCore() async {
    requests++;
    return AuthorizeCode.error;
  }
}
