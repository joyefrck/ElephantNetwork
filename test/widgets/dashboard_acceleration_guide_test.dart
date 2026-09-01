import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/widgets/acceleration_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits for a profile before showing the guide', (tester) async {
    final profiles = _TestProfiles([]);
    final container = _container(profiles: profiles);
    addTearDown(container.dispose);

    await _pumpDashboard(tester, container);

    expect(find.byType(DashboardAccelerationGuide), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    profiles.replace([_profile]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
    expect(find.text('点击右下角“开启加速”，开始使用'), findsOneWidget);
  });

  testWidgets('does not show a completed guide', (tester) async {
    final container = _container(
      completed: true,
      profiles: _TestProfiles([_profile]),
    );
    addTearDown(container.dispose);

    await _pumpDashboard(tester, container);

    expect(find.byType(DashboardAccelerationGuide), findsNothing);
  });

  testWidgets('shows only while the dashboard is current', (tester) async {
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);
    container.read(currentPageLabelProvider.notifier).toPage(PageLabel.account);

    await _pumpDashboard(tester, container);

    expect(find.byType(DashboardAccelerationGuide), findsNothing);
    expect(
      container.read(appSettingProvider).dashboardAccelerationGuideCompleted,
      isFalse,
    );

    container
        .read(currentPageLabelProvider.notifier)
        .toPage(PageLabel.dashboard);
    await tester.pump();
    await tester.pump();

    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
  });

  testWidgets('leaving without a button tap keeps the guide incomplete', (
    tester,
  ) async {
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);

    await _pumpDashboard(tester, container);
    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: SizedBox.shrink()),
      ),
    );

    expect(
      container.read(appSettingProvider).dashboardAccelerationGuideCompleted,
      isFalse,
    );

    await _pumpDashboard(tester, container);
    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
  });

  testWidgets('running acceleration completes the guide without showing it', (
    tester,
  ) async {
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);
    container.read(runTimeProvider.notifier).value = 1;

    await _pumpDashboard(tester, container);
    await tester.pump();

    expect(find.byType(DashboardAccelerationGuide), findsNothing);
    expect(
      container.read(appSettingProvider).dashboardAccelerationGuideCompleted,
      isTrue,
    );
  });

  testWidgets('outside taps are blocked and the highlighted button completes', (
    tester,
  ) async {
    final events = <bool>[];
    final container = _container(
      profiles: _TestProfiles([_profile]),
      setupAction: _RecordingSetupAction(events),
    );
    addTearDown(container.dispose);

    await _pumpDashboard(tester, container);

    await tester.tapAt(tester.getCenter(find.byIcon(Icons.edit)));
    await tester.pump();
    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.save), findsNothing);
    expect(events, isEmpty);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(events, [true]);
    expect(find.byType(DashboardAccelerationGuide), findsNothing);
    expect(
      container.read(appSettingProvider).dashboardAccelerationGuideCompleted,
      isTrue,
    );
  });

  testWidgets('root overlay blocks controls outside the dashboard', (
    tester,
  ) async {
    var menuTapCount = 0;
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: TextButton(
                  key: const Key('external-menu-action'),
                  onPressed: () {
                    menuTapCount++;
                  },
                  child: const Text('代理'),
                ),
              ),
              const Expanded(child: DashboardView()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('external-menu-action'))),
    );
    await tester.pump();

    expect(menuTapCount, 0);
    expect(find.byType(DashboardAccelerationGuide), findsOneWidget);
  });

  for (final size in [const Size(390, 720), const Size(1200, 800)]) {
    testWidgets('spotlight follows the real button at ${size.width}', (
      tester,
    ) async {
      final container = _container(profiles: _TestProfiles([_profile]));
      addTearDown(container.dispose);

      await _pumpDashboard(tester, container, size: size);

      final guide = tester.widget<DashboardAccelerationGuide>(
        find.byType(DashboardAccelerationGuide),
      );
      final overlayOrigin = tester.getTopLeft(
        find.byKey(const Key('dashboard-acceleration-guide')),
      );
      final buttonRect = tester.getRect(find.byType(FloatingActionButton));
      final targetRect = guide.targetRect.shift(overlayOrigin);

      expect((targetRect.center - buttonRect.center).distance, lessThan(0.5));
      expect(
        (targetRect.size.width - buttonRect.size.width).abs(),
        lessThan(1),
      );
      expect(
        (targetRect.size.height - buttonRect.size.height).abs(),
        lessThan(1),
      );
    });
  }

  testWidgets('spotlight repositions when the same window resizes', (
    tester,
  ) async {
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);
    await _pumpDashboard(tester, container);

    tester.view.physicalSize = const Size(600, 700);
    await tester.pump();
    await tester.pump();

    final guide = tester.widget<DashboardAccelerationGuide>(
      find.byType(DashboardAccelerationGuide),
    );
    final overlayOrigin = tester.getTopLeft(
      find.byKey(const Key('dashboard-acceleration-guide')),
    );
    final targetRect = guide.targetRect.shift(overlayOrigin);
    final buttonRect = tester.getRect(find.byType(FloatingActionButton));

    expect((targetRect.center - buttonRect.center).distance, lessThan(0.5));
    expect((targetRect.width - buttonRect.width).abs(), lessThan(1));
  });

  testWidgets('spotlight follows the button after the locale changes', (
    tester,
  ) async {
    final container = _container(profiles: _TestProfiles([_profile]));
    addTearDown(container.dispose);
    await _pumpDashboard(tester, container);
    final initialWidth = tester
        .getSize(find.byType(FloatingActionButton))
        .width;

    await _pumpDashboard(tester, container, locale: const Locale('en'));

    final guide = tester.widget<DashboardAccelerationGuide>(
      find.byType(DashboardAccelerationGuide),
    );
    final overlayOrigin = tester.getTopLeft(
      find.byKey(const Key('dashboard-acceleration-guide')),
    );
    final targetRect = guide.targetRect.shift(overlayOrigin);
    final buttonRect = tester.getRect(find.byType(FloatingActionButton));

    expect(buttonRect.width, isNot(initialWidth));
    expect((targetRect.center - buttonRect.center).distance, lessThan(0.5));
    expect((targetRect.width - buttonRect.width).abs(), lessThan(1));
  });
}

ProviderContainer _container({
  required _TestProfiles profiles,
  bool completed = false,
  SetupAction? setupAction,
}) {
  return ProviderContainer(
    overrides: [
      appSettingProvider.overrideWithBuild(
        (_, _) =>
            AppSettingProps(dashboardAccelerationGuideCompleted: completed),
      ),
      dashboardStateProvider.overrideWithValue(
        const DashboardState(dashboardWidgets: []),
      ),
      initProvider.overrideWithBuild((_, _) => true),
      profilesProvider.overrideWith(() => profiles),
      suspendProvider.overrideWithValue(false),
      if (setupAction != null)
        setupActionProvider.overrideWith(() => setupAction),
    ],
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1200, 800),
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _TestApp(locale: locale, child: const DashboardView()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

const _profile = Profile(id: 1, autoUpdateDuration: Duration.zero);

class _TestProfiles extends Profiles {
  _TestProfiles(this.initial);

  final List<Profile> initial;

  @override
  List<Profile> build() => initial;

  void replace(List<Profile> profiles) {
    state = profiles;
  }
}

class _RecordingSetupAction extends SetupAction {
  _RecordingSetupAction(this.events);

  final List<bool> events;

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    events.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({this.locale = const Locale('zh', 'CN'), required this.child});

  final Locale locale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: locale,
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
