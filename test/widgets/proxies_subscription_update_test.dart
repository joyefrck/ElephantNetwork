import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty proxy layouts retain update and settings actions', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpView(tester, container, () async => true);

    for (final type in ProxiesType.values) {
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(type: type));
      await tester.pump();
      expect(find.text('Update subscription'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.adjust), findsNothing);
    }

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'subscription failure can be retried without an existing profile',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final completion = Completer<bool>();
      var calls = 0;
      await _pumpView(tester, container, () {
        calls++;
        return calls == 1 ? Future.value(false) : completion.future;
      });
      final button = find.byKey(const Key('proxies-update-subscription'));

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.text('Unable to update the subscription. Please try again.'),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await tester.drag(find.byType(Dismissible), const Offset(800, 0));
      await tester.pumpAndSettle();

      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(calls, 2);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      completion.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      expect(find.text('Subscription updated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('update recovers from exceptions and tolerates disposal', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    final completion = Completer<bool>();
    var calls = 0;
    await _pumpView(tester, container, () {
      if (++calls == 1) throw StateError('subscription unavailable');
      return completion.future;
    });
    final button = find.byKey(const Key('proxies-update-subscription'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.tap(button);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    completion.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    profilesProvider.overrideWith(_EmptyProfiles.new),
    viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
  ],
);

Future<void> _pumpView(
  WidgetTester tester,
  ProviderContainer container,
  Future<bool> Function() sync,
) async {
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: globalState.navigatorKey,
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
          globalState.theme = CommonTheme.of(context, 1);
          return StatusManager(child: child!);
        },
        home: ProxiesView(syncSubscription: sync),
      ),
    ),
  );
  await tester.pump();
}

class _EmptyProfiles extends Profiles {
  @override
  List<Profile> build() => [];
}
