import 'package:fl_clash/common/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'primary navigation keeps exactly four ordered items with logs on or off',
    () {
      const expected = [
        PageLabel.dashboard,
        PageLabel.proxies,
        PageLabel.account,
        PageLabel.tools,
      ];
      for (final openLogs in [false, true]) {
        final items = navigation.getItems(openLogs: openLogs);
        for (final mode in [
          NavigationItemMode.desktop,
          NavigationItemMode.mobile,
        ]) {
          expect(
            items
                .where((item) => item.modes.contains(mode))
                .map((item) => item.label),
            expected,
            reason: '$mode, openLogs=$openLogs',
          );
        }
        expect(
          items
              .where((item) => item.modes.contains(NavigationItemMode.more))
              .any((item) => item.label == PageLabel.logs),
          openLogs,
        );
      }
    },
  );
}
