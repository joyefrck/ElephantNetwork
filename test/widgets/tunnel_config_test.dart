import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/tunnel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSystem extends SystemAction {
  Completer<void>? pending;
  Object? failure;
  int calls = 0;
  bool requestedTun = false;

  @override
  Future<void> configureApns(
    NetworkProps settings, {
    bool enableTun = false,
  }) async {
    calls++;
    requestedTun = enableTun;
    await pending?.future;
    if (failure != null) throw failure!;
    ref.read(networkSettingProvider.notifier).value = settings;
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
    globalState.container = container;
  });
  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          builder: (context, child) {
            globalState.measure = Measure.of(context, 1);
            return child!;
          },
          home: const TunnelConfigView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one click requests TUN and proxy routing and ignores repeat taps',
    (tester) async {
      action.pending = Completer<void>();
      await open(tester);
      await tester.tap(find.text('Enable Apple push proxy'));
      await tester.pump();
      expect(action.requestedTun, true);
      expect(find.text('Applying…'), findsOneWidget);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(action.calls, 1);
      action.pending!.complete();
      await tester.pumpAndSettle();
      expect(container.read(networkSettingProvider).includeApns, true);
      expect(container.read(networkSettingProvider).apnsRoute, ApnsRoute.proxy);
      expect(find.text('Applying…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failure clears progress and allows retry', (tester) async {
    action.failure = StateError('TUN denied');
    await open(tester);
    await tester.tap(find.text('Enable Apple push proxy'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Unable to apply push settings'),
      150,
    );
    expect(find.text('Unable to apply push settings'), findsOneWidget);
    expect(container.read(networkSettingProvider).includeApns, false);
    action.failure = null;
    await tester.scrollUntilVisible(find.text('Enable Apple push proxy'), -150);
    await tester.tap(find.text('Enable Apple push proxy'));
    await tester.pumpAndSettle();
    expect(action.calls, 2);
    expect(container.read(networkSettingProvider).includeApns, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the page during apply does not update disposed state', (
    tester,
  ) async {
    action.pending = Completer<void>();
    await open(tester);
    await tester.tap(find.text('Enable Apple push proxy'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    action.pending!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });
}
