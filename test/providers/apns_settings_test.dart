import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSystem extends SystemAction {
  Object? failure;
  Completer<void>? pending;
  final applied = <NetworkProps>[];

  @override
  Future<void> selectProxyMode({required bool tun}) async {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: tun));
  }

  @override
  Future<void> applyApnsProfile() async {
    applied.add(ref.read(networkSettingProvider));
    await pending?.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  late ProviderContainer container;
  late _TestSystem action;

  setUp(() {
    action = _TestSystem();
    container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    container.listen(configProvider, (_, _) {}, fireImmediately: true);
    container.read(systemActionProvider);
  });
  tearDown(() => container.dispose());

  test('one click enables TUN and rule mode before applying APNs', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.direct));
    await action.configureApns(
      const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
      enableTun: true,
    );
    expect(container.read(patchClashConfigProvider).tun.enable, true);
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  test(
    'persists APNs choices while retaining unrelated network settings',
    () async {
      await action.configureApns(
        const NetworkProps(
          includeApns: true,
          apnsRoute: ApnsRoute.proxy,
          apnsProxy: 'Exit',
        ),
      );
      expect(container.read(networkSettingProvider).includeApns, true);
      expect(container.read(networkSettingProvider).apnsProxy, 'Exit');
      expect(container.read(networkSettingProvider).systemProxy, true);
      expect(action.applied.single.apnsRoute, ApnsRoute.proxy);
    },
  );

  test(
    'failed apply restores APNs settings without reverting concurrent network edits',
    () async {
      action.pending = Completer<void>();
      action.failure = StateError('apply failed');
      final operation = action.configureApns(
        const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
      );
      final expectation = expectLater(operation, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      container
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(appendSystemDns: true));
      action.pending!.complete();
      await expectation;
      expect(container.read(networkSettingProvider).includeApns, false);
      expect(container.read(networkSettingProvider).appendSystemDns, true);
    },
  );

  test(
    'serializes rapid edits and leaves the latest requested state',
    () async {
      action.pending = Completer<void>();
      final first = action.configureApns(
        const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
      );
      final second = action.configureApns(
        const NetworkProps(includeApns: false, apnsRoute: ApnsRoute.direct),
      );
      await Future<void>.delayed(Duration.zero);
      expect(action.applied, hasLength(1));
      action.pending!.complete();
      await Future.wait([first, second]);
      expect(action.applied, hasLength(2));
      expect(container.read(networkSettingProvider).includeApns, false);
      expect(
        container.read(networkSettingProvider).apnsRoute,
        ApnsRoute.direct,
      );
    },
  );
}
