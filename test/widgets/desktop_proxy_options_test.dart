import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/views/dashboard/widgets/quick_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpOptions(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(_ReadySetup.new)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
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
            return child!;
          },
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: TUNButton()),
                      Expanded(child: SystemProxyButton()),
                    ],
                  ),
                  TUNItem(),
                  SystemProxyItem(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Finder toggle(Type parent) =>
      find.descendant(of: find.byType(parent), matching: find.byType(Switch));

  void expectSwitches(WidgetTester tester, bool tun) {
    for (final type in [TUNButton, TUNItem]) {
      expect(tester.widget<Switch>(toggle(type)).value, tun);
    }
    for (final type in [SystemProxyButton, SystemProxyItem]) {
      expect(tester.widget<Switch>(toggle(type)).value, !tun);
    }
  }

  testWidgets('cards show the agreed names and usage scenarios', (
    tester,
  ) async {
    await pumpOptions(tester);
    expect(find.text('虚拟网卡（TUN）'), findsNWidgets(2));
    expect(find.text('网页与日常应用'), findsOneWidget);
    expect(find.text('游戏、ChatGPT、Claude等'), findsOneWidget);
    expect(find.text('选项'), findsNothing);
    expectSwitches(tester, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usage scenarios fit a narrow dashboard row', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOptions(tester);
    expect(find.text('游戏、ChatGPT、Claude等'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards and settings share one exclusive selection', (
    tester,
  ) async {
    final container = await pumpOptions(tester);
    await tester.tap(toggle(TUNButton));
    await tester.pumpAndSettle();
    expectSwitches(tester, true);
    expect(container.read(networkSettingProvider).systemProxy, isFalse);

    await tester.tap(toggle(TUNItem));
    await tester.pumpAndSettle();
    expectSwitches(tester, true);

    await tester.tap(toggle(SystemProxyItem));
    await tester.pumpAndSettle();
    expectSwitches(tester, false);

    await tester.tap(toggle(SystemProxyButton));
    await tester.pumpAndSettle();
    expectSwitches(tester, false);
    expect(tester.takeException(), isNull);
  });
}

class _ReadySetup extends SetupAction {
  @override
  Future<void> prepareDesktopTun() async {}

  @override
  Future<void> applyDesktopTun(bool enable) async {}
}
