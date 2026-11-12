import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CustomAction extends ProfilesAction {
  int calls = 0;
  String? label;
  bool fail = false;
  Completer<Profile>? pending;

  @override
  Future<Profile> createCustomProfile({String? label}) async {
    calls++;
    this.label = label;
    if (fail) throw StateError('fixture import failure');
    return pending?.future ?? Profile.custom(label: label);
  }
}

void main() {
  Future<ProviderContainer> pumpView(
    WidgetTester tester,
    _CustomAction action,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [profilesActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(900, 800);
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
            builder: (context) =>
                Scaffold(body: AddProfileView(context: context)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> submit(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.text('Create custom profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'My local config');
    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }
  }

  testWidgets('custom creation enters the existing profile tools flow', (
    tester,
  ) async {
    final action = _CustomAction();
    final container = await pumpView(tester, action);
    await submit(tester);
    expect(action.calls, 1);
    expect(action.label, 'My local config');
    expect(container.read(currentPageLabelProvider), PageLabel.profiles);
    expect(container.read(loadingProvider(LoadingTag.profiles)), false);
  });

  testWidgets('failed creation clears loading and permits retry', (
    tester,
  ) async {
    final action = _CustomAction()..fail = true;
    final container = await pumpView(tester, action);
    await submit(tester);
    expect(container.read(loadingProvider(LoadingTag.profiles)), false);
    expect(action.calls, 1);
    expect(
      find.textContaining('fixture import failure', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pumpAndSettle();
    action.fail = false;
    await submit(tester);
    expect(action.calls, 2);
    expect(container.read(currentPageLabelProvider), PageLabel.profiles);
  });

  testWidgets('completion after disposal does not navigate', (tester) async {
    final action = _CustomAction()..pending = Completer<Profile>();
    final container = await pumpView(tester, action);
    final original = container.read(currentPageLabelProvider);
    await submit(tester, settle: false);
    await tester.pumpWidget(const SizedBox());
    action.pending!.complete(Profile.custom());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(currentPageLabelProvider), original);
    expect(container.read(loadingProvider(LoadingTag.profiles)), false);
    expect(tester.takeException(), isNull);
  });
}
