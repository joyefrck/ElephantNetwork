import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/network_detection.dart'
    as dashboard;
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the resolved node above a smaller exit IP', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pumpCard(tester, container);

    final node = find.text('Korea HY2');
    final ip = find.text('203.0.113.28');
    expect(find.text('Current node:'), findsOneWidget);
    expect(node, findsOneWidget);
    expect(ip, findsOneWidget);
    expect(tester.getBottomLeft(node).dy, lessThan(tester.getTopLeft(ip).dy));
    expect(
      tester.widget<Text>(ip).style!.fontSize,
      lessThan(tester.widget<Text>(node).style!.fontSize!),
    );
    expect(tester.takeException(), isNull);

    container.read(groupsProvider.notifier).value = [
      ..._groups.take(2),
      const Group(name: 'Automatic', type: GroupType.URLTest, now: 'Japan HY2'),
    ];
    await tester.pumpAndSettle();

    expect(find.text('Korea HY2'), findsNothing);
    expect(find.text('Japan HY2'), findsOneWidget);
  });

  testWidgets('highlights only the node name beside the Chinese label', (
    tester,
  ) async {
    final container = _container(
      groups: const [
        Group(name: 'Exit', type: GroupType.Selector, now: '美国-专线1'),
      ],
    );
    addTearDown(container.dispose);
    await _pumpCard(tester, container, locale: const Locale('zh', 'CN'));

    final label = find.text('当前节点：');
    final node = find.text('美国-专线1');
    final badge = find
        .ancestor(of: node, matching: find.byType(DecoratedBox))
        .first;
    final decoration =
        tester.widget<DecoratedBox>(badge).decoration as BoxDecoration;
    expect(decoration.border, isA<Border>());
    expect((decoration.border! as Border).top.width, 1);
    expect(find.descendant(of: badge, matching: label), findsNothing);
    expect(
      tester.getTopLeft(badge).dx,
      greaterThan(tester.getTopRight(label).dx),
    );
    expect(tester.getSize(badge).width, lessThan(220));
    expect(find.text('203.0.113.28'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global mode follows GLOBAL rather than the rule group', (
    tester,
  ) async {
    final container = _container(mode: Mode.global);
    addTearDown(container.dispose);
    await _pumpCard(tester, container);

    expect(find.text('US node'), findsOneWidget);
    expect(find.text('Korea HY2'), findsNothing);
  });

  for (final running in [false, true]) {
    testWidgets('direct mode reflects running=$running', (tester) async {
      final container = _container(mode: Mode.direct, running: running);
      addTearDown(container.dispose);
      await _pumpCard(tester, container);

      expect(find.text(running ? 'Direct' : 'Disconnected'), findsOneWidget);
      expect(find.text('Korea HY2'), findsNothing);
      expect(find.text('203.0.113.28'), findsOneWidget);
    });
  }

  for (final loading in [false, true]) {
    testWidgets('retains the node while IP loading=$loading', (tester) async {
      final container = _container(
        detection: NetworkDetectionState(isLoading: loading, ipInfo: null),
      );
      addTearDown(container.dispose);
      await _pumpCard(tester, container);

      expect(find.text('Korea HY2'), findsOneWidget);
      expect(find.text('Timeout'), loading ? findsNothing : findsOneWidget);
      expect(
        find.byType(CommonCircleLoading),
        loading ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long node and IPv6 fit a narrow card', (tester) async {
    const name = 'Korea HY2 very long node name with a region and port 443';
    final container = _container(
      groups: const [Group(name: 'Exit', type: GroupType.Selector, now: name)],
      detection: const NetworkDetectionState(
        isLoading: false,
        ipInfo: IpInfo(
          ip: '2001:db8:1234:5678:90ab:cdef:1234:5678',
          countryCode: 'KR',
        ),
      ),
    );
    addTearDown(container.dispose);
    await _pumpCard(tester, container, width: 240);

    expect(
      tester.widget<Text>(find.text(name)).overflow,
      TextOverflow.ellipsis,
    );
    expect(find.byTooltip(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing groups use a placeholder while retaining the IP', (
    tester,
  ) async {
    final container = _container(groups: const []);
    addTearDown(container.dispose);
    await _pumpCard(tester, container);

    expect(find.text('--'), findsOneWidget);
    expect(find.text('203.0.113.28'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _groups = [
  Group(name: 'GLOBAL', type: GroupType.Selector, now: 'US node'),
  Group(name: 'Exit', type: GroupType.Selector, now: 'Automatic'),
  Group(name: 'Automatic', type: GroupType.URLTest, now: 'Korea HY2'),
];

ProviderContainer _container({
  Mode mode = Mode.rule,
  bool running = true,
  List<Group> groups = _groups,
  NetworkDetectionState detection = const NetworkDetectionState(
    isLoading: false,
    ipInfo: IpInfo(ip: '203.0.113.28', countryCode: 'KR'),
  ),
}) {
  return ProviderContainer(
    overrides: [
      networkDetectionProvider.overrideWithBuild((_, _) => detection),
      isStartProvider.overrideWithValue(running),
      suspendProvider.overrideWithValue(false),
      patchClashConfigProvider.overrideWithBuild(
        (_, _) => PatchClashConfig(mode: mode),
      ),
      groupsProvider.overrideWithBuild((_, _) => groups),
      selectedMapProvider.overrideWithValue(const {}),
    ],
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 320,
  Locale locale = const Locale('en'),
}) async {
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
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
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const dashboard.NetworkDetection(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
