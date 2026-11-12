import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid Windows install dates do not prevent startup', () async {
    expect(
      await loadPlatformDeviceInfo<int>(
        read: () async => throw RangeError('InstallDate'),
        windows: true,
      ),
      isNull,
    );
  });
  test(
    'normal device information and unrelated failures stay intact',
    () async {
      expect(
        await loadPlatformDeviceInfo(read: () async => 11, windows: true),
        11,
      );
      await expectLater(
        loadPlatformDeviceInfo<int>(
          read: () async => throw RangeError('other platform'),
          windows: false,
        ),
        throwsRangeError,
      );
      await expectLater(
        loadPlatformDeviceInfo<int>(
          read: () async => throw StateError('plugin unavailable'),
          windows: true,
        ),
        throwsStateError,
      );
    },
  );
}
