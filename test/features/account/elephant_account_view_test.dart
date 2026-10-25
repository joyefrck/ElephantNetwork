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
    await _pumpAccount(tester);

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
  testWidgets('shows the current effective product below the account email', (
    tester,
  ) async {
    for (final type in ['plan', 'traffic_package']) {
      await _pumpAccount(tester, {
        'has_active_plan': type == 'plan',
        'active_product_type': type,
        'active_product_name': '有效套餐 600G',
      });
      final email = find.text('owner@example.com');
      final plan = find.text('当前套餐：有效套餐 600G');
      expect(plan, findsOneWidget);
      expect(
        tester.getTopLeft(plan).dy,
        greaterThan(tester.getBottomLeft(email).dy),
      );
      expect(find.text('余额'), findsOneWidget);
      expect(find.text('套餐流量'), findsOneWidget);
    }
  });

  testWidgets('shows an explicit empty state without an effective product', (
    tester,
  ) async {
    await _pumpAccount(tester, {
      'has_active_plan': false,
      'active_product_type': 'none',
      'active_product_name': null,
      'plan_id': 10,
      'expired_at': 1,
    });
    expect(find.text('当前套餐：暂无有效套餐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAccount(
  WidgetTester tester, [
  Map<String, Object?> fields = const {},
]) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        xboardSessionControllerProvider.overrideWithValue(
          XboardSessionState.authenticated(
            XboardSession(
              token: 'token',
              account: XboardAccount.fromJson({
                'email': 'owner@example.com',
                ...fields,
              }),
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
}
