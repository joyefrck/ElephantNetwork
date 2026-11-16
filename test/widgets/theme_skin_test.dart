import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeProps skin fields', () {
    test('default to the ocean voyage skin and its colors', () {
      const props = ThemeProps();
      expect(props.skin, ThemeSkin.ocean);
      expect(props.skinImagePath, isNull);
      expect(props.skinOpacity, defaultSkinOpacity);
      expect(defaultThemeProps.skin, ThemeSkin.ocean);
      expect(defaultThemeProps.primaryColor, ThemeSkin.ocean.seedColor);
      expect(ThemeProps.safeFromJson(null), defaultThemeProps);
    });

    test('unknown skin names fall back to none without losing settings', () {
      final props = ThemeProps.safeFromJson({
        'skin': 'futureSkin',
        'themeMode': 'dark',
        'skinOpacity': 0.2,
      });
      expect(props.skin, ThemeSkin.none);
      expect(props.themeMode, ThemeMode.dark);
      expect(props.skinOpacity, 0.2);
    });

    test('settings saved before skins get the ocean voyage look', () {
      final untouched = ThemeProps.safeFromJson({
        'primaryColor': defaultPrimaryColor,
        'themeMode': 'dark',
        'pureBlack': true,
      });
      expect(untouched.skin, ThemeSkin.ocean);
      expect(untouched.primaryColor, ThemeSkin.ocean.seedColor);
      expect(untouched.themeMode, ThemeMode.dark);

      final customized = ThemeProps.safeFromJson({'primaryColor': 0xFF123456});
      expect(customized.skin, ThemeSkin.ocean);
      expect(customized.primaryColor, 0xFF123456);

      final chosen = ThemeProps.safeFromJson({
        'skin': 'none',
        'primaryColor': defaultPrimaryColor,
      });
      expect(chosen.skin, ThemeSkin.none);
      expect(chosen.primaryColor, defaultPrimaryColor);
    });

    test('round-trips through json', () {
      const props = ThemeProps(
        skin: ThemeSkin.custom,
        skinImagePath: '/tmp/skin.png',
        skinOpacity: 0.08,
      );
      final json = jsonDecode(jsonEncode(props)) as Map<String, Object?>;
      expect(ThemeProps.fromJson(json), props);
    });

    test('every skin can be saved and loaded back', () {
      for (final skin in ThemeSkin.values) {
        final props = defaultThemeProps.copyWith(skin: skin);
        final encoded = jsonEncode(Config(themeProps: props));
        final decoded = Config.fromJson(
          jsonDecode(encoded) as Map<String, Object?>,
        );
        expect(decoded.themeProps.skin, skin, reason: skin.name);
      }
    });

    test('every skin except my picture carries a seed color', () {
      for (final skin in ThemeSkin.values) {
        expect(
          skin.seedColor != null,
          skin != ThemeSkin.custom,
          reason: skin.name,
        );
      }
      expect(ThemeSkin.none.seedColor, 0xFFFFFFFF);
    });
  });

  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1200, 1600));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
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
            return ThemeSkinOverlay(child: child!);
          },
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  void setSkin(ThemeSkin skin) {
    container
        .read(themeSettingProvider.notifier)
        .update((state) => state.copyWith(skin: skin));
  }

  testWidgets('overlay is absent without a skin and passes taps through', (
    tester,
  ) async {
    var taps = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: FilledButton(onPressed: () => taps++, child: const Text('go')),
        ),
      ),
    );
    expect(find.byType(ThemeSkinLayer), findsOneWidget);

    setSkin(ThemeSkin.none);
    await tester.pump();
    expect(find.byType(ThemeSkinLayer), findsNothing);

    setSkin(ThemeSkin.ocean);
    await tester.pump();
    expect(find.byType(ThemeSkinLayer), findsOneWidget);

    await tester.tap(find.text('go'));
    expect(taps, 1);

    setSkin(ThemeSkin.custom);
    await tester.pump();
    expect(find.byType(ThemeSkinLayer), findsNothing);
  });

  testWidgets('picking a named skin applies its art and colors', (
    tester,
  ) async {
    await pumpApp(tester, const ThemeView());

    for (final label in [
      '简约',
      '蜡笔涂鸦',
      '大海冒险',
      '樱花物语',
      '星空夜行',
      '喵喵午后',
      '少年侦探',
      '小小船长',
      '灯笼夜行',
      '我的图片',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.text('纯黑模式'), findsNothing);
    expect(container.read(themeSettingProvider).skin, ThemeSkin.ocean);
    expect(find.byKey(const ValueKey('theme_skin_opacity')), findsOneWidget);

    await tester.tap(find.text('蜡笔涂鸦'));
    await tester.pumpAndSettle();
    expect(container.read(themeSettingProvider).skin, ThemeSkin.crayon);

    await tester.tap(find.text('大海冒险'));
    await tester.pumpAndSettle();
    final props = container.read(themeSettingProvider);
    expect(props.skin, ThemeSkin.ocean);
    expect(props.primaryColor, ThemeSkin.ocean.seedColor);
    expect(find.byKey(const ValueKey('theme_skin_opacity')), findsOneWidget);

    await tester.tap(find.text('简约'));
    await tester.pumpAndSettle();
    expect(container.read(themeSettingProvider).skin, ThemeSkin.none);
    expect(container.read(themeSettingProvider).primaryColor, 0xFFFFFFFF);
    expect(find.byKey(const ValueKey('theme_skin_opacity')), findsNothing);
  });

  testWidgets('theme page has no custom color or pure black controls', (
    tester,
  ) async {
    await pumpApp(tester, const ThemeView());
    expect(find.text('自定义颜色'), findsNothing);
    expect(find.text('纯黑模式'), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsNothing);
  });
}
