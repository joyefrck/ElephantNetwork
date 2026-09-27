import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows storage identity is independent from FlClash', () {
    final resource = File('windows/runner/Runner.rc').readAsStringSync();
    String resourceValue(String key) =>
        RegExp('VALUE "$key", "([^"]+)"').firstMatch(resource)!.group(1)!;

    expect(resourceValue('CompanyName'), 'com.elephantroute');
    expect(resourceValue('ProductName'), 'ElephantNetwork');
    expect(
      '${resourceValue('CompanyName')}\\${resourceValue('ProductName')}',
      isNot(r'com.follow\clash'),
    );
  });

  test(
    'Windows helper endpoints and build outputs use one isolated identity',
    () {
      expect(appHelperService, 'ElephantNetworkHelperService');
      expect(helperPort, isNot(47890));
      expect(windowsPipeName, startsWith(r'\\.\pipe\ElephantNetworkCore_'));
      final hub = File('services/helper/src/service/hub.rs').readAsStringSync();
      expect(hub, contains('LISTEN_PORT: u16 = $helperPort;'));
      expect(hub, contains('"$helperProtocolVersionHeader"'));
      expect(hub, contains(r'\\.\pipe\ElephantNetworkCore_'));
      final service = File(
        'services/helper/src/service/windows.rs',
      ).readAsStringSync();
      expect(service, contains('SERVICE_NAME: &str = "$appHelperService"'));
      final cmake = File(
        'plugins/setup/windows/CMakeLists.txt',
      ).readAsStringSync();
      expect(cmake, contains('$appHelperService.exe'));
      final config = File(
        'plugins/setup/buildkit/build_tool/build_config.yaml',
      ).readAsStringSync();
      expect(config, contains('helper_name: $appHelperService'));
      final installer = File(
        'windows/packaging/exe/inno_setup.iss',
      ).readAsStringSync();
      expect(installer, contains('$appHelperService.exe'));
      expect(installer, isNot(contains("'FlClash.exe'")));
      expect(installer, isNot(contains("'/f /im '")));
      expect(installer, contains('GetDirectoryName(\$_.ExecutablePath) -eq'));
      expect(installer, contains('CompareText(Trim(ImagePath), HelperPath)'));
    },
  );
}
