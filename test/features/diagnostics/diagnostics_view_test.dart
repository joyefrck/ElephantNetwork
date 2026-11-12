import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/diagnostics/diagnostics_controller.dart';
import 'package:fl_clash/features/diagnostics/quality_repository.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'diagnostics_controller_test.dart' show FakeCore;

void main() {
  testWidgets('narrow diagnostics view supports cancel and leaving the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final core = FakeCore();
    final controller = DiagnosticsController(
      core: core,
      qualityRepository: QualityRepository(
        dao: db.ipQualitiesDao,
        lookup: (_, _) async => throw StateError('unused'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        diagnosticsProvider.overrideWith((ref) {
          ref.onDispose(controller.dispose);
          return controller;
        }),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        isStartProvider.overrideWithValue(false),
        suspendProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
          home: const DiagnosticsView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    expect(core.proxies, ['DIRECT', 'DIRECT']);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(core.canceled, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(core.watches.last, isFalse);
  });
}
