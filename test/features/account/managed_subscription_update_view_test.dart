import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only the current account managed subscription', (
    tester,
  ) async {
    final current = _profile('Current subscription');
    final container = _container([
      Profile.normal(label: 'User profile'),
      _profile('Other account', ownerAccountId: 'other@example.com'),
      current,
    ]);
    addTearDown(container.dispose);

    await _pumpView(tester, container: container);

    expect(find.text('Current subscription'), findsOneWidget);
    expect(find.text('User profile'), findsNothing);
    expect(find.text('Other account'), findsNothing);
    expect(find.byKey(const Key('managed-subscription-sync')), findsOneWidget);
  });

  testWidgets('updates automatic settings and validates the interval', (
    tester,
  ) async {
    final profile = _profile('Managed');
    final container = _container([profile]);
    addTearDown(container.dispose);
    await _pumpView(tester, container: container);

    await tester.tap(
      find.byKey(const Key('managed-subscription-auto-update')).first,
    );
    await tester.pump();

    expect(container.read(profilesProvider).single.autoUpdate, isFalse);
    expect(
      find.byKey(const Key('managed-subscription-update-interval')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('managed-subscription-auto-update')).first,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('managed-subscription-update-interval')).first,
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    final invalidValues = <String, String>{
      '': 'Please enter the auto update interval time',
      'abc': 'Please input a valid interval time format',
      '0': 'Auto update interval must be greater than 0',
      '-5': 'Auto update interval must be greater than 0',
    };
    for (final entry in invalidValues.entries) {
      await tester.enterText(field, entry.key);
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    }

    await tester.enterText(field, '60');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(
      container.read(profilesProvider).single.autoUpdateDuration,
      const Duration(minutes: 60),
    );
  });

  testWidgets('prevents duplicate synchronization while pending', (
    tester,
  ) async {
    final completer = Completer<bool>();
    var calls = 0;
    final container = _container([_profile('Managed')]);
    addTearDown(container.dispose);
    await _pumpView(
      tester,
      container: container,
      sync: () {
        calls++;
        return completer.future;
      },
    );

    final target = find.byKey(const Key('managed-subscription-sync'));
    await tester.tap(target);
    await tester.pump();

    expect(calls, 1);
    expect(tester.widget<FilledButton>(target).onPressed, isNull);

    completer.complete(true);
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(target).onPressed, isNotNull);
  });

  testWidgets('shows retry state and handles synchronization failure', (
    tester,
  ) async {
    var calls = 0;
    final container = _container(const []);
    addTearDown(container.dispose);
    await _pumpView(
      tester,
      container: container,
      sync: () async {
        calls++;
        return false;
      },
    );

    expect(
      find.text(
        'Signed in, but the managed subscription could not be loaded. '
        'Please retry later.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending synchronization is safe when the view is disposed', (
    tester,
  ) async {
    final completer = Completer<bool>();
    final container = _container([_profile('Managed')]);
    addTearDown(container.dispose);
    await _pumpView(tester, container: container, sync: () => completer.future);

    await tester.tap(find.byKey(const Key('managed-subscription-sync')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(false);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Profile _profile(String label, {String ownerAccountId = 'owner@example.com'}) {
  return Profile.normal(
    label: label,
    url: 'https://example.com/subscription',
  ).copyWith(
    source: ProfileSource.xboard,
    ownerAccountId: ownerAccountId,
    lastUpdateDate: DateTime.now(),
  );
}

ProviderContainer _container(List<Profile> profiles) {
  return ProviderContainer(
    overrides: [
      xboardSessionControllerProvider.overrideWithValue(
        const XboardSessionState.authenticated(
          XboardSession(token: 'token', account: _account),
        ),
      ),
      viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 1000)),
      profilesProvider.overrideWith(() => _TestProfiles(profiles)),
    ],
  );
}

Future<void> _pumpView(
  WidgetTester tester, {
  required ProviderContainer container,
  ManagedSubscriptionSync? sync,
}) async {
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _TestApp(child: ManagedSubscriptionUpdateView(sync: sync)),
    ),
  );
  await tester.pump();
}

const _account = XboardAccount(
  email: 'owner@example.com',
  balance: 0,
  upload: 0,
  download: 0,
  planTransferEnable: 0,
  planUsedTraffic: 0,
  planRemainingTraffic: 0,
  trafficPackageTotal: 0,
  trafficPackageRemaining: 0,
  effectiveTransferEnable: 0,
  effectiveRemainingTraffic: 0,
);

class _TestProfiles extends Profiles {
  _TestProfiles(this.initial);

  final List<Profile> initial;

  @override
  List<Profile> build() => initial;

  @override
  void updateProfile(int profileId, Profile Function(Profile profile) builder) {
    state = [
      for (final profile in state)
        if (profile.id == profileId) builder(profile) else profile,
    ];
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: child,
    );
  }
}
