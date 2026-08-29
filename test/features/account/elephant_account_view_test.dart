import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('website action is left aligned and shares the title baseline', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          xboardSessionControllerProvider.overrideWithValue(
            const XboardSessionState.authenticated(
              XboardSession(
                token: 'token',
                account: XboardAccount(
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
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: const ElephantAccountView(),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('个人概览');
    final button = find.byKey(const Key('open-website-button'));
    final buttonLabel = find.text('打开官网');
    expect(title, findsOneWidget);
    expect(buttonLabel, findsOneWidget);
    expect(button, findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isFalse);
    expect(tester.getTopLeft(title).dx, lessThan(40));
    expect(
      tester.getTopLeft(button).dx,
      greaterThan(tester.getTopRight(title).dx),
    );
    expect(
      tester.getTopLeft(button).dx - tester.getTopRight(title).dx,
      lessThanOrEqualTo(8),
    );

    final titleRow = tester.widget<Row>(
      find.ancestor(of: button, matching: find.byType(Row)).first,
    );
    expect(titleRow.crossAxisAlignment, CrossAxisAlignment.baseline);
    expect(titleRow.textBaseline, TextBaseline.alphabetic);

    final label = tester.widget<Text>(buttonLabel);
    final labelTheme = Theme.of(tester.element(buttonLabel)).textTheme;
    expect(label.style?.fontSize, labelTheme.labelLarge?.fontSize);
    expect(label.style?.decoration, TextDecoration.underline);
  });
}
