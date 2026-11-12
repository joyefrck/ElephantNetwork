import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

class _Setup extends SetupAction {
  @override
  void autoApplyProfile() {}
}

class _SaveAction extends ProfilesAction {
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> putProfile(Profile profile) async {
    calls++;
    if (fail) throw StateError('fixture save failure');
    await pending?.future;
  }
}

void main() {
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('profile-save-');
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDownAll(() => root.delete(recursive: true));

  Future<void> openEditor(WidgetTester tester, _SaveAction action) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(_Setup.new),
        profilesActionProvider.overrideWith(() => action),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(900, 800);
    final profile = Profile.normal(label: 'Local');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            globalState.measure = Measure.of(context, 1);
            globalState.theme = CommonTheme.of(context, 1);
            return child!;
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: EditProfileView(context: context, profile: profile),
                    ),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets('save failure keeps the form editable and retry succeeds', (
    tester,
  ) async {
    final action = _SaveAction()..fail = true;
    await openEditor(tester, action);
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('fixture save failure', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(EditProfileView), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
    action.fail = false;
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(action.calls, 2);
    expect(find.byType(EditProfileView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending save disables duplicate submissions', (tester) async {
    final action = _SaveAction()..pending = Completer<void>();
    await openEditor(tester, action);
    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byIcon(Icons.save), warnIfMissed: false);
    expect(action.calls, 1);
    action.pending!.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EditProfileView), findsNothing);
  });

  testWidgets(
    'save finishing after the editor closes does not pop another route',
    (tester) async {
      final action = _SaveAction()..pending = Completer<void>();
      await openEditor(tester, action);
      await tester.tap(find.byIcon(Icons.save));
      await tester.pump();
      globalState.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      action.pending!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Open editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
