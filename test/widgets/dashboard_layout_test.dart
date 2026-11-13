import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/widgets/grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard removes retired cards from existing settings', () {
    final container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            dashboardWidgets: [
              DashboardWidget.outboundModeV2,
              DashboardWidget.intranetIp,
              DashboardWidget.memoryInfo,
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final widgets = container.read(dashboardStateProvider).dashboardWidgets;
    expect(widgets.first, DashboardWidget.intranetIp);
    expect(widgets, isNot(contains(DashboardWidget.outboundModeV2)));
    expect(widgets, isNot(contains(DashboardWidget.memoryInfo)));
    expect(widgets, containsAll(defaultDashboardWidgets));
    expect(container.read(checkIpProvider).c, isTrue);
  });

  testWidgets('dashboard limits a wide grid to 16 centered columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(dashboardWidgets: []),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    final grid = find.byType(Grid);
    final dashboardGrid = tester.widget<Grid>(grid);
    expect(dashboardGrid.crossAxisCount, 16);
    expect(
      dashboardGrid.children,
      DashboardWidget.values
          .where(
            (item) =>
                item != DashboardWidget.outboundModeV2 &&
                item != DashboardWidget.memoryInfo &&
                item.platforms.contains(SupportPlatform.currentPlatform),
          )
          .map((item) => item.widget),
    );
    expect(tester.getSize(grid).width, 1120);
    expect(tester.getTopLeft(grid).dx, 240);
    expect(find.text(AppLocalizations.current.memoryInfo), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.save), findsNothing);
    expect(find.byIcon(Icons.add_circle), findsNothing);
    expect(tester.takeException(), null);
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
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
      home: child,
    );
  }
}
