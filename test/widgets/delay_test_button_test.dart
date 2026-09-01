import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'keeps the delay test label visible when the page collapses FABs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: const Scaffold(
            floatingActionButton: CommonScaffoldFabExtendedProvider(
              isExtended: false,
              child: DelayTestButton(onClick: Future<void>.value),
            ),
          ),
        ),
      );

      expect(find.text('延迟测试'), findsOneWidget);
    },
  );
}
