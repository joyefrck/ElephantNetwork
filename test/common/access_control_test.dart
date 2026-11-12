import 'package:fl_clash/common/access_control.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in AccessControlMode.values) {
    test('sorting $mode preserves hidden and uninstalled selections', () {
      final props = AccessControlProps(
        mode: mode,
        acceptList: const [
          'org.hidden.app',
          'org.visible.app',
          'org.hidden.app',
        ],
        rejectList: const ['org.removed.app'],
      );
      final saved = sortedAccessControl(props);
      expect(saved.acceptList, ['org.hidden.app', 'org.visible.app']);
      expect(saved.rejectList, ['org.removed.app']);
      expect(props.acceptList.length, 3);
    });
  }

  test('smart selection changes visible apps and preserves hidden choices', () {
    const props = AccessControlProps(
      acceptList: ['org.hidden.app', 'org.china.app'],
      rejectList: ['org.removed.app', 'org.global.app'],
    );
    final next = selectVisibleApplications(
      props,
      const [
        Package(
          packageName: 'org.hidden.app',
          label: 'Hidden',
          system: true,
          internet: true,
          lastUpdateTime: 0,
        ),
        Package(
          packageName: 'org.china.app',
          label: 'China',
          system: false,
          internet: true,
          lastUpdateTime: 0,
        ),
        Package(
          packageName: 'org.global.app',
          label: 'Global',
          system: false,
          internet: true,
          lastUpdateTime: 0,
        ),
      ],
      {'org.china.app'},
    );
    expect(next.acceptList, ['org.hidden.app', 'org.global.app']);
    expect(next.rejectList, ['org.removed.app', 'org.china.app']);
  });

  test('clipboard parsing trims, validates and deduplicates package names', () {
    expect(
      parseAccessPackageNames(
        ' org.example.app \r\n\norg.example.app\ninvalid\ncom.vendor_app.main\n https://example.com\n',
      ),
      ['org.example.app', 'com.vendor_app.main'],
    );
    expect(parseAccessPackageNames(' \nnot a package\n-\n'), isEmpty);
  });
}
