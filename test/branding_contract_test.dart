import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fork identity and GPL notices remain explicit', () {
    final constants = File('lib/common/constant.dart').readAsStringSync();
    final submodules = File('.gitmodules').readAsStringSync();
    final notice = File('NOTICE');
    final upstream = File('docs/UPSTREAM.md');

    expect(constants, contains("const appName = 'Elephant Network';"));
    expect(constants, contains("const repository = 'joyefrck/ElephantNetwork';"));
    expect(
      submodules,
      contains('url = https://github.com/chen08209/Clash.Meta.git'),
    );
    expect(File('LICENSE').existsSync(), isTrue);
    expect(notice.existsSync(), isTrue);
    expect(notice.readAsStringSync(), contains('GNU General Public License'));
    expect(notice.readAsStringSync(), contains('chen08209/FlClash'));
    expect(upstream.existsSync(), isTrue);
    expect(upstream.readAsStringSync(), contains('upstream/main'));
    expect(
      sha256.convert(File('assets/images/icon.png').readAsBytesSync()).toString(),
      'e33eca5618b59c7afd58422e0df70c9f9c990f2335229c30cdd649d1ecd17dad',
    );
    expect(
      sha256
          .convert(
            File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
          )
          .toString(),
      'f9a196b8cd8e9fdcfd32c5e34f8c618a2196ab89316052be14ad3d5a0be35456',
    );
  });
}
