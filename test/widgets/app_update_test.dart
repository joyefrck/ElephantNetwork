import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/features/update/app_update_client.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'Elephant Network',
      packageName: 'com.elephantroute',
      version: '2.1.0',
      buildNumber: '21000',
    );
  });

  testWidgets(
    'startup immediately checks even with an old disabled preference',
    (tester) async {
      final client = _FakeClient();
      final container = await _pumpApp(tester, client, autoCheckUpdate: false);
      final check = container
          .read(commonActionProvider.notifier)
          .autoCheckUpdate();
      expect(client.calls, 1);
      expect(client.currentVersion, '2.1.0');
      expect(client.currentBuild, '21000');
      await tester.pumpAndSettle();

      final message = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(message.textSpan!.toPlainText(), contains('v2.1.0 (Build 21001)'));
      expect(message.textSpan!.toPlainText(), contains(_notes));
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await check;
    },
  );

  testWidgets('cancel keeps future checks enabled and allows the next prompt', (
    tester,
  ) async {
    final client = _FakeClient();
    final container = await _pumpApp(tester, client);
    final action = container.read(commonActionProvider.notifier);
    for (var attempt = 0; attempt < 2; attempt++) {
      final check = action.autoCheckUpdate();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await check;
      expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
    }
    expect(client.calls, 2);
  });

  testWidgets('overlapping automatic and manual checks show one dialog', (
    tester,
  ) async {
    final client = _FakeClient()..pending = Completer<Map<String, dynamic>?>();
    final container = await _pumpApp(tester, client);
    final action = container.read(commonActionProvider.notifier);
    final automatic = action.autoCheckUpdate();
    final manual = action.checkUpdate();
    expect(client.calls, 1);
    client.pending!.complete(_release);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await Future.wait([automatic, manual]);
  });

  testWidgets('update opens the official installer download', (tester) async {
    final client = _FakeClient();
    final container = await _pumpApp(tester, client);
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    final check = container.read(commonActionProvider.notifier).checkUpdate();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    await check;

    expect(calls.single.arguments['url'], _release['download_url']);
    expect(calls.single.arguments['useWebView'], isFalse);
    expect(calls.single.arguments['useSafariVC'], isFalse);
  });

  testWidgets('no release or an offline startup does not interrupt the app', (
    tester,
  ) async {
    final client = _FakeClient()..result = null;
    final container = await _pumpApp(tester, client);
    final action = container.read(commonActionProvider.notifier);
    await action.autoCheckUpdate();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    client.error = StateError('offline');
    await action.autoCheckUpdate();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the app during a check does not open a dialog', (
    tester,
  ) async {
    final client = _FakeClient()..pending = Completer<Map<String, dynamic>?>();
    final container = await _pumpApp(tester, client);
    final check = container
        .read(commonActionProvider.notifier)
        .autoCheckUpdate();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    client.pending!.complete(_release);
    await check;
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing release notes show a readable fallback', (tester) async {
    final client = _FakeClient()..result = {..._release, 'body': ''};
    final container = await _pumpApp(tester, client);
    final check = container
        .read(commonActionProvider.notifier)
        .autoCheckUpdate();
    await tester.pumpAndSettle();
    final message = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(
      message.textSpan!.toPlainText(),
      contains('No release notes provided'),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await check;
  });

  testWidgets('unmounting the app during a manual check skips its result', (
    tester,
  ) async {
    final client = _FakeClient()..pending = Completer<Map<String, dynamic>?>();
    final container = await _pumpApp(tester, client);
    final check = container.read(commonActionProvider.notifier).checkUpdate();
    await tester.pumpWidget(const SizedBox.shrink());
    client.pending!.complete(null);
    await check;
    expect(tester.takeException(), isNull);
  });

  testWidgets('long release notes keep both actions accessible on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _FakeClient()
      ..result = {
        ..._release,
        'body': List.generate(80, (index) => 'Improvement $index').join('\n'),
      };
    final container = await _pumpApp(tester, client);
    final check = container
        .read(commonActionProvider.notifier)
        .autoCheckUpdate();
    await tester.pumpAndSettle();
    expect(find.text('Update').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await check;
  });

  testWidgets('a failed manual check can be retried', (tester) async {
    final client = _FakeClient()..error = StateError('offline');
    final container = await _pumpApp(tester, client);
    final action = container.read(commonActionProvider.notifier);
    final first = action.checkUpdate();
    await tester.pumpAndSettle();
    final message = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(message.textSpan!.toPlainText(), contains('Network exception'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await first;

    client.error = null;
    final retry = action.checkUpdate();
    await tester.pumpAndSettle();
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await retry;
    expect(client.calls, 2);
  });
}

const _notes =
    'Improved login\n\nPasswords no longer clear the email.\n1. Updated icons';
const _release = <String, dynamic>{
  'tag_name': 'v2.1.0',
  'build_number': 21001,
  'body': _notes,
  'download_url': 'https://downloads.example/elephant-network.pkg',
};

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  _FakeClient client, {
  bool autoCheckUpdate = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      appUpdateClientProvider.overrideWithValue(client),
      appSettingProvider.overrideWithBuild(
        (_, _) => AppSettingProps(autoCheckUpdate: autoCheckUpdate),
      ),
      viewSizeProvider.overrideWithBuild((_, _) => const Size(800, 600)),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: globalState.navigatorKey,
        locale: const Locale('en'),
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
        home: const Scaffold(body: Text('app')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _FakeClient implements AppUpdateClient {
  int calls = 0;
  String? currentVersion;
  String? currentBuild;
  Map<String, dynamic>? result = _release;
  Object? error;
  Completer<Map<String, dynamic>?>? pending;

  @override
  Future<Map<String, dynamic>?> check({
    required String version,
    required String build,
  }) async {
    calls++;
    currentVersion = version;
    currentBuild = build;
    if (error != null) throw error!;
    return pending?.future ?? result;
  }
}
