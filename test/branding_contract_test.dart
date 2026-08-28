import 'dart:io';

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
  });
}
