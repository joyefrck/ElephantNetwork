import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production identities remain compatible with Elephant Network 1.6.9', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final constants = File('lib/common/constant.dart').readAsStringSync();
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final components = File(
      'android/common/src/main/java/com/follow/clash/common/Components.kt',
    ).readAsStringSync();
    final macos = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final windows = File(
      'windows/packaging/exe/make_config.yaml',
    ).readAsStringSync();

    expect(pubspec, contains('version: 2.0.0+20000'));
    expect(constants, contains("const packageName = 'com.elephantroute';"));
    expect(android, contains('applicationId = "com.elephantroute"'));
    expect(components, contains('PACKAGE_NAME = "com.elephantroute"'));
    expect(components, contains('CLASS_PACKAGE_NAME = "com.follow.clash"'));
    expect(macos, contains('PRODUCT_NAME = ElephantRoute'));
    expect(
      macos,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = com.elphantroute.elephantNetwork',
      ),
    );
    expect(
      windows,
      contains('app_id: "{{5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245}"'),
    );
    expect(windows, contains('executable_name: ElephantNetwork.exe'));
  });

  test('upstream Firebase wiring is absent', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final app = File('android/app/build.gradle.kts').readAsStringSync();
    final common = File('android/common/build.gradle.kts').readAsStringSync();
    final workflow = File('.github/workflows/build.yaml').readAsStringSync();

    expect(settings, isNot(contains('com.google.firebase')));
    expect(settings, isNot(contains('com.google.gms.google-services')));
    expect(app, isNot(contains('firebase')));
    expect(common, isNot(contains('firebase')));
    expect(workflow, isNot(contains('SERVICE_JSON')));
    expect(File('android/app/google-services.json').existsSync(), isFalse);
  });
}
