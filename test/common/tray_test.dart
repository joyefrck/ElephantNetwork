import 'package:fl_clash/common/tray.dart';
import 'package:test/test.dart';

void main() {
  group('trayIconPath', () {
    test('Windows uses distinct running and stopped icons', () {
      expect(
        trayIconPath(operatingSystem: 'windows', isStart: true),
        'assets/images/tray_windows_active.ico',
      );
      expect(
        trayIconPath(operatingSystem: 'windows', isStart: false),
        'assets/images/tray_windows_inactive.ico',
      );
    });

    for (final isStart in [false, true]) {
      test('macOS keeps its template icon when isStart=$isStart', () {
        expect(
          trayIconPath(operatingSystem: 'macos', isStart: isStart),
          'assets/images/tray_macos.png',
        );
      });

      test('Linux keeps its application icon when isStart=$isStart', () {
        expect(
          trayIconPath(operatingSystem: 'linux', isStart: isStart),
          'assets/images/icon.png',
        );
      });
    }
  });
}
