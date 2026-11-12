import 'dart:async';

import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

void main() {
  Future<ProviderContainer> pumpManager(
    WidgetTester tester,
    CoreHandlerInterface handler,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CoreManager(
            controller: CoreController.test(handler),
            child: const SizedBox(),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets(
    'log requests wait for connection and converge to the newest toggle',
    (tester) async {
      final handler = _MockCoreHandlerInterface();
      final started = Completer<void>();
      when(() => handler.startLog()).thenAnswer((_) => started.future);
      when(() => handler.stopLog()).thenAnswer((_) async {});
      final container = await pumpManager(tester, handler);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(openLogs: true));
      await tester.pump();
      verifyNever(() => handler.startLog());
      verifyNever(() => handler.stopLog());
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      verify(() => handler.startLog()).called(1);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(openLogs: false));
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(openLogs: true));
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(openLogs: false));
      await tester.pump();
      verifyNever(() => handler.stopLog());
      started.complete();
      await tester.pump();
      verify(() => handler.stopLog()).called(1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'log failures are contained and reconnect reapplies the setting',
    (tester) async {
      final handler = _MockCoreHandlerInterface();
      var attempts = 0;
      when(() => handler.stopLog()).thenAnswer((_) async {
        if (++attempts == 1) {
          throw const CoreMethodException(
            code: 'transport_disconnected',
            message: 'gone',
          );
        }
      });
      final container = await pumpManager(tester, handler);
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(attempts, 1);
      container.read(coreStatusProvider.notifier).value =
          CoreStatus.disconnected;
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an old pending log request cannot block a reconnect or survive disposal',
    (tester) async {
      final handler = _MockCoreHandlerInterface();
      final pending = Completer<void>();
      var attempts = 0;
      when(() => handler.stopLog()).thenAnswer(
        (_) => ++attempts == 1 ? pending.future : Future<void>.value(),
      );
      final container = await pumpManager(tester, handler);
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      container.read(coreStatusProvider.notifier).value =
          CoreStatus.disconnected;
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await tester.pump();
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox());
      pending.completeError(
        const CoreMethodException(
          code: 'transport_disconnected',
          message: 'old link',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(attempts, 2);
    },
  );

  testWidgets('duplicate crash events disconnect the core only once', (
    tester,
  ) async {
    final coreInterface = _MockCoreHandlerInterface();
    when(() => coreInterface.stopLog()).thenAnswer((_) {});
    final controller = CoreController.test(coreInterface);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CoreManager(controller: controller, child: const SizedBox()),
        ),
      ),
    );
    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    final transitions = <CoreStatus>[];
    final subscription = container.listen<CoreStatus>(
      coreStatusProvider,
      (_, next) => transitions.add(next),
    );
    addTearDown(subscription.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    const crash = CoreEvent(type: CoreEventType.crash, data: 'boom');
    coreEventManager.sendEvent(crash);
    coreEventManager.sendEvent(crash);
    await tester.pump();

    expect(container.read(coreStatusProvider), CoreStatus.disconnected);
    expect(transitions, [CoreStatus.disconnected]);
    verifyNever(() => coreInterface.stop());

    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
