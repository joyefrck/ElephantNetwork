import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'Elephant Network',
      packageName: 'com.elphantroute.elephantNetwork',
      version: '2.0.1',
      buildNumber: '20001',
    );
  });

  final entryStates = <String, XboardSessionState>{
    'unauthenticated': const XboardSessionState.unauthenticated(),
    'unavailable': XboardSessionState.unavailable(
      StateError('secure_storage_unavailable'),
    ),
  };

  for (final entry in entryStates.entries) {
    testWidgets('${entry.key} uses the light login entry', (tester) async {
      await _pumpGate(tester, entry.value);

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Sign in'), findsOneWidget);
      final fieldContext = tester.element(find.byType(TextFormField).first);
      expect(Theme.of(fieldContext).brightness, Brightness.light);
      expect(
        Theme.of(fieldContext).scaffoldBackgroundColor,
        const Color(0xFFF6F8F5),
      );
      expect(find.text('v2.0.1'), findsOneWidget);
    });
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets('login shows the package version on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpGate(tester, const XboardSessionState.unauthenticated());

        expect(find.byKey(const Key('xboard-login-version')), findsOneWidget);
        expect(find.text('v2.0.1'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('session wait shows branding and the login email only', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      const XboardSessionState.loading(email: 'owner@example.com'),
    );

    expect(find.text('Elephant Network'), findsOneWidget);
    expect(find.text('Hello, owner@example.com'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('active login wait shows the submitted email only', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      const XboardSessionState.authenticating('owner@example.com'),
    );

    expect(find.text('Hello, owner@example.com'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('authenticated child keeps the parent dark theme', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      XboardSessionState.authenticated(
        XboardSession(token: 'token', account: _account()),
      ),
    );

    final childContext = tester.element(find.byKey(const Key('child')));
    expect(Theme.of(childContext).brightness, Brightness.dark);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('rejected login shows a credential-specific error', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      const XboardSessionState.unauthenticated(
        XboardApiException(statusCode: 400),
      ),
    );

    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(
      find.text('Elephant Network is temporarily unavailable'),
      findsNothing,
    );
  });
}

Future<void> _pumpGate(WidgetTester tester, XboardSessionState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [xboardSessionControllerProvider.overrideWithValue(state)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: const XboardGate(child: Builder(builder: _authenticatedChild)),
      ),
    ),
  );
  await tester.pump();
}

Widget _authenticatedChild(BuildContext context) {
  return const Text('authenticated', key: Key('child'));
}

XboardAccount _account() {
  return const XboardAccount(
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
}
