import 'dart:io';

import 'package:fl_clash/common/tray.dart';
import 'package:test/test.dart';

void main() {
  group('Tray.trayIconPath', () {
    final tray = Tray();
    final suffix = tray.trayIconSuffix;

    test('returns the application logo', () {
      expect(
        tray.trayIconPath,
        Platform.isMacOS
            ? 'assets/images/tray_macos.png'
            : 'assets/images/icon.$suffix',
      );
    });
  });
}
