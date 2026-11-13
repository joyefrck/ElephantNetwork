import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late _ResetSystem action;
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'Elephant Network',
      packageName: 'test',
      version: '2.1.0',
      buildNumber: '1',
    );
  });

  Future<void> pumpTools(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    action = _ResetSystem();
    final container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1200, 1200));
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
            return child!;
          },
          home: const ToolsView(),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('恢复默认配置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('恢复默认配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('reset sits below application and cancellation changes nothing', (
    tester,
  ) async {
    await pumpTools(tester);
    expect(
      tester.getTopLeft(find.text('应用程序')).dy,
      lessThan(tester.getTopLeft(find.text('恢复默认配置')).dy),
    );
    await tester.tap(find.text('恢复默认配置'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText(),
      contains('登录账号、订阅和节点数据将保留'),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(action.calls, 0);
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
  });

  testWidgets('confirmed reset blocks repeated taps and restores the button', (
    tester,
  ) async {
    await pumpTools(tester);
    action.pending = Completer<void>();
    await confirm(tester);
    expect(action.calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('恢复默认配置'));
    await tester.pump();
    expect(action.calls, 1);
    action.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure clears progress and permits another attempt', (
    tester,
  ) async {
    await pumpTools(tester);
    action.failure = StateError('save failed');
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
    action.failure = null;
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(action.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion after disposal does not update the removed widget', (
    tester,
  ) async {
    await pumpTools(tester);
    action.pending = Completer<void>();
    await confirm(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    action.pending!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _ResetSystem extends SystemAction {
  int calls = 0;
  Completer<void>? pending;
  Object? failure;

  @override
  Future<void> restoreDefaultSettings() async {
    calls++;
    await pending?.future;
    if (failure != null) throw failure!;
  }
}
