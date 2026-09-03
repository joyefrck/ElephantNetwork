import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production identities remain compatible with Elephant Network 1.6.9',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final constants = File('lib/common/constant.dart').readAsStringSync();
      final android = File('android/app/build.gradle.kts').readAsStringSync();
      final components = File(
        'android/common/src/main/java/com/follow/clash/common/Components.kt',
      ).readAsStringSync();
      final macos = File(
        'macos/Runner/Configs/AppInfo.xcconfig',
      ).readAsStringSync();
      final macosProject = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final macosReleaseEntitlements = File(
        'macos/Runner/Release.entitlements',
      ).readAsStringSync();
      final macosDebugEntitlements = File(
        'macos/Runner/DebugProfile.entitlements',
      ).readAsStringSync();
      final sessionStore = File(
        'lib/features/account/xboard_session_store.dart',
      ).readAsStringSync();
      final windows = File(
        'windows/packaging/exe/make_config.yaml',
      ).readAsStringSync();

      expect(pubspec, contains('version: 2.0.4+20004'));
      expect(pubspec, contains('flutter_secure_storage: 10.0.0'));
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
      expect(macosProject, contains('CODE_SIGN_IDENTITY = "-";'));
      expect(
        macosProject,
        contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'),
      );
      expect(macosProject, contains('CODE_SIGN_STYLE = Manual;'));
      expect(
        macosReleaseEntitlements,
        isNot(contains('<key>keychain-access-groups</key>')),
      );
      expect(
        macosDebugEntitlements,
        isNot(contains('<key>keychain-access-groups</key>')),
      );
      expect(
        sessionStore,
        contains('usesDataProtectionKeychain: false'),
      );
      expect(
        sessionStore,
        contains("'useDataProtectionKeyChain': 'false'"),
      );
      expect(
        windows,
        contains('app_id: "{{5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245}"'),
      );
      expect(
        windows,
        contains(r'setup_icon_file: windows\runner\resources\app_icon.ico'),
      );
      expect(
        windows,
        contains(r'file: ..\windows\packaging\exe\ChineseSimplified.isl'),
      );
      expect(
        File('windows/runner/resources/app_icon.ico').existsSync(),
        isTrue,
      );
      expect(
        File('windows/packaging/exe/ChineseSimplified.isl').existsSync(),
        isTrue,
      );
      expect(windows, contains('executable_name: ElephantNetwork.exe'));
    },
  );

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

  test('manual workflow builds unsigned desktop installers', () {
    final workflow = File('.github/workflows/build.yaml').readAsStringSync();

    expect(workflow, contains('unsigned-desktop-build:'));
    expect(workflow, contains('platform: windows'));
    expect(workflow, contains('target: exe'));
    expect(workflow, contains('platform: macos'));
    expect(workflow, contains('target: dmg'));
    expect(workflow, contains("if: github.event_name == 'workflow_dispatch'"));
  });
}
