import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in AccessControlMode.values) {
    testWidgets('saving $mode keeps selected apps hidden by filters', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 800)),
          packagesProvider.overrideWithBuild(
            (_, _) => const [
              Package(
                packageName: 'org.hidden.app',
                label: 'Hidden',
                system: true,
                internet: true,
                lastUpdateTime: 0,
              ),
              Package(
                packageName: 'org.visible.app',
                label: 'Visible',
                system: false,
                internet: true,
                lastUpdateTime: 0,
              ),
            ],
          ),
          vpnSettingProvider.overrideWithBuild(
            (_, _) => VpnProps(
              accessControlProps: AccessControlProps(
                enable: true,
                mode: mode,
                acceptList: const ['org.hidden.app'],
                rejectList: const ['org.hidden.app'],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
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
            home: const AccessView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(accessControlStateProvider.notifier)
          .update(
            (value) =>
                value.copyWithNewList(['org.hidden.app', 'org.visible.app']),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        container.read(vpnSettingProvider).accessControlProps.currentList,
        ['org.hidden.app', 'org.visible.app'],
      );
      expect(tester.takeException(), isNull);
    });
  }
}
