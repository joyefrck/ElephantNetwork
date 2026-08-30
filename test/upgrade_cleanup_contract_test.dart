import 'dart:io';

import 'package:fl_clash/common/legacy_upgrade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android identity and signing gate support an in-place upgrade', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final verifier = File(
      'tool/verify_android_upgrade_signature.sh',
    ).readAsStringSync();

    expect(pubspec, contains('version: 2.0.0+20000'));
    expect(gradle, contains('applicationId = "com.elephantroute"'));
    expect(verifier, contains('apksigner'));
    expect(verifier, contains('Android upgrade signature mismatch'));
  });

  test('Windows installer owns the legacy service and proxy cleanup', () {
    final source = File(
      'windows/packaging/exe/inno_setup.iss',
    ).readAsStringSync();
    final config = File(
      'windows/packaging/exe/make_config.yaml',
    ).readAsStringSync();

    expect(config, contains('5F1D7A6E-2B3C-4A91-9D74-E0C8F6B1A245'));
    expect(source, contains('delete ElephantNetworkService'));
    expect(source, contains('sing-box-windows-amd64.exe'));
    expect(source, contains("CompareText(ProxyServer, '127.0.0.1:2334')"));
    expect(source, contains('AppVerName={{DISPLAY_NAME}}'));
    expect(source, contains('UninstallDisplayName={{DISPLAY_NAME}}'));
    expect(
      source,
      contains(r'UninstallDisplayIcon={app}\\{{EXECUTABLE_NAME}}'),
    );
  });

  test('macOS cleanup targets only the legacy privileged components', () {
    final source = File(
      'assets/scripts/cleanup_legacy_macos.sh',
    ).readAsStringSync();

    expect(source, contains(LegacyUpgradeCleaner.helperPath));
    expect(source, contains(LegacyUpgradeCleaner.plistPath));
    expect(source, contains('sing-box-darwin'));
    expect(source, isNot(contains('Application Support/FlClash')));
  });
}
