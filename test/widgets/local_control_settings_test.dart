import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            globalState.measure = Measure.of(context, 1);
            globalState.theme = CommonTheme.of(context, 1);
            return child!;
          },
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ExternalControllerItem(),
                  ControllerSecretItem(),
                  LocalProxyAuthenticationItem(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'controller toggle creates a persistent key and exposes copying only when enabled',
    (tester) async {
      final container = await pumpSettings(tester);
      expect(find.text('Controller access key'), findsNothing);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      final enabled = container.read(patchClashConfigProvider);
      expect(enabled.externalController, ExternalControllerStatus.open);
      expect(isValidControllerSecret(enabled.secret), true);
      expect(find.text('Controller access key'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Controller access key'), findsNothing);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(container.read(patchClashConfigProvider).secret, enabled.secret);
    },
  );

  testWidgets(
    'proxy authentication generates credentials and conceals the password',
    (tester) async {
      final container = await pumpSettings(tester);
      expect(find.text('Proxy username'), findsNothing);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      final auth = container.read(networkSettingProvider).authentication;
      expect(auth.enable, true);
      expect(auth.isValid, true);
      expect(find.text(auth.username), findsOneWidget);
      expect(find.text(auth.password), findsNothing);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(find.text('Proxy username'), findsNothing);
      expect(
        container.read(networkSettingProvider).authentication.username,
        auth.username,
      );
    },
  );
}
