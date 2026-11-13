import 'dart:typed_data';
import 'dart:ui';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/theme_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/start_button.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _buttonBoundaryKey = ValueKey('button-boundary');

void main() {
  for (final running in [false, true]) {
    testWidgets(
      'start button hover stays visually stable with running=$running',
      (tester) async {
        final container = _createContainer();
        addTearDown(container.dispose);
        container.read(runTimeProvider.notifier).value = running ? 39000 : null;
        await _pumpButton(tester, container, const StartButton());
        await _checkHover(tester);
      },
    );
  }

  testWidgets('delay test button hover stays visually stable', (tester) async {
    final container = _createContainer();
    addTearDown(container.dispose);
    await _pumpButton(
      tester,
      container,
      const DelayTestButton(onClick: Future<void>.value),
    );
    await _checkHover(tester);
  });
}

ProviderContainer _createContainer() {
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWithValue([
        const Profile(id: 1, autoUpdateDuration: Duration.zero),
      ]),
      suspendProvider.overrideWithValue(false),
    ],
  );
  globalState.container = container;
  return container;
}

Future<void> _pumpButton(
  WidgetTester tester,
  ProviderContainer container,
  Widget button,
) async {
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
        builder: (_, child) => ThemeManager(child: child!),
        home: Scaffold(
          floatingActionButton: RepaintBoundary(
            key: _buttonBoundaryKey,
            child: button,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _checkHover(WidgetTester tester) async {
  final button = find.byType(FloatingActionButton);
  final initialRect = tester.getRect(button);
  final material = find.descendant(of: button, matching: find.byType(Material));
  final initialElevation = tester.widget<Material>(material).elevation;
  final initialPixels = await _captureButton(tester);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  for (final position in [
    initialRect.center,
    initialRect.topLeft + const Offset(18, 2),
    initialRect.topRight + const Offset(-18, 2),
    initialRect.bottomRight + const Offset(-18, -2),
    initialRect.center,
    Offset.zero,
  ]) {
    await mouse.moveTo(position);
    await tester.pump();
    expect(tester.widget<Material>(material).elevation, initialElevation);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(tester.getRect(button), initialRect);
    expect(await _captureButton(tester), orderedEquals(initialPixels));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  }
  for (final reverse in [false, true, false, true]) {
    for (var step = 0; step <= 8; step++) {
      final progress = reverse ? 1 - step / 8 : step / 8;
      await mouse.moveTo(
        Offset(
          initialRect.left - 8 + (initialRect.width + 16) * progress,
          initialRect.center.dy,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(button), initialRect);
      expect(tester.widget<Material>(material).elevation, initialElevation);
      expect(await _captureButton(tester), orderedEquals(initialPixels));
      expect(tester.takeException(), isNull);
    }
  }
  await tester.pumpAndSettle();
  expect(tester.binding.hasScheduledFrame, isFalse);
}

Future<Uint8List> _captureButton(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_buttonBoundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData();
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}
