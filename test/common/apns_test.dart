import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/apns.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _config() => {
  'tun': {
    'enable': true,
    'route-address': ['10.0.0.0/8'],
    'route-exclude-address': ['17.0.0.0/8', '10.0.0.0/8', '2403:300::/32'],
  },
  'dns': {
    'enhanced-mode': 'fake-ip',
    'fake-ip-filter-mode': 'whitelist',
    'fake-ip-filter': ['*.example.com'],
  },
  'proxy-groups': [
    {
      'name': 'Exit',
      'type': 'select',
      'proxies': ['Node'],
    },
  ],
  'proxies': [
    {'name': 'Node', 'type': 'ss'},
  ],
  'rules': ['DOMAIN-SUFFIX,apple.com,DIRECT', 'MATCH,Exit'],
};

Future<CompiledProfile> _compile(NetworkProps settings) => compileProfileTask(
  MakeRealProfileState(
    profilesPath: '/profiles',
    profileId: 1,
    rawConfig: _config(),
    realPatchConfig: const PatchClashConfig(tun: Tun(enable: true)),
    networkProps: settings,
    profileSource: ProfileSource.xboard,
    overrideDns: false,
    appendSystemDns: false,
    proxyGroups: const [],
    rules: const [],
    addedRules: const [],
    defaultUA: 'test',
  ),
);

void main() {
  test('old settings remain disabled and settings round trip', () {
    expect(NetworkProps.fromJson({}).includeApns, false);
    const settings = NetworkProps(
      includeApns: true,
      apnsRoute: ApnsRoute.proxy,
      apnsProxy: 'Exit',
    );
    expect(NetworkProps.fromJson(jsonDecode(jsonEncode(settings))), settings);
  });

  test('disabled policy leaves the original configuration intact', () {
    final config = _config();
    final original = jsonEncode(config);
    applyApnsPolicy(config, const NetworkProps());
    expect(jsonEncode(config), original);
  });

  test('APNs rules precede Apple direct rules and retain DNS semantics', () {
    final config = _config();
    final dns = jsonEncode(config['dns']);
    applyApnsPolicy(
      config,
      const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
    );
    final rules = config['rules'] as List;
    expect(rules.first, contains('(DOMAIN-SUFFIX,push.apple.com)),Exit'));
    expect(rules[1], contains('(PROCESS-NAME,apsd)),Exit'));
    expect(
      rules,
      contains(contains('(IP-CIDR6,2403:300:a42::/48,no-resolve)')),
    );
    expect(
      rules
          .take(11)
          .every((rule) => rule.toString().contains('(DST-PORT,5223/443)')),
      true,
    );
    expect(rules.last, 'MATCH,Exit');
    expect(jsonEncode(config['dns']), dns);
    expect(config['tun']['route-address'], containsAll(apnsNetworks));
    expect(config['tun']['route-address'], contains('198.18.0.0/16'));
  });

  test('follow rules does not force an outbound and direct forces DIRECT', () {
    final config = _config();
    applyApnsPolicy(config, const NetworkProps(includeApns: true));
    expect(config['rules'], _config()['rules']);
    applyApnsPolicy(
      config,
      const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.direct),
    );
    expect((config['rules'] as List).first, endsWith(',DIRECT'));
  });

  test('missing saved targets fall back to a valid profile outbound', () {
    expect(resolveApnsProxy(_config(), 'Old subscription'), 'Exit');
    expect(resolveApnsProxy(_config(), 'Node'), 'Node');
    expect(
      resolveApnsProxy({
        'rules': ['MATCH,DIRECT'],
      }, null),
      isNull,
    );
    expect(
      () => applyApnsPolicy(
        {},
        const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
      ),
      throwsStateError,
    );
  });

  test('includes APNs with legacy route configuration and Fake-IP pools', () {
    final config = _config();
    config['tun'] = {
      'inet4-route-address': ['10.0.0.0/8'],
      'inet4-route-exclude-address': ['17.248.0.0/15'],
    };
    applyApnsPolicy(config, const NetworkProps(includeApns: true));
    expect(config['tun']['route-address'], contains('198.18.0.0/16'));
    expect(config['tun']['route-address'], containsAll(apnsNetworks));
    expect(config['tun']['inet4-route-address'], isNull);
    expect(config['tun']['inet4-route-exclude-address'], ['17.248.0.0/16']);
  });

  test('subtracts only APNs networks from excluded IPv4 and IPv6 routes', () {
    expect(excludeApnsNetworks(['10.0.0.0/8']), ['10.0.0.0/8']);
    expect(excludeApnsNetworks(['17.249.0.0/16']), isEmpty);
    expect(excludeApnsNetworks(['17.249.1.0/24']), isEmpty);
    expect(excludeApnsNetworks(['17.248.0.0/15']), ['17.248.0.0/16']);
    expect(excludeApnsNetworks(['2403:300:a42::/47']), ['2403:300:a43::/48']);
    expect(excludeApnsNetworks(['::/0']), isNot(contains('::/0')));
  });

  test(
    'compilation applies APNs only on macOS after managed DNS policy',
    () async {
      final enabled = await _compile(
        const NetworkProps(includeApns: true, apnsRoute: ApnsRoute.proxy),
      );
      final config = loadYaml(enabled.yaml);
      if (!Platform.isMacOS) {
        expect(config['rules'].toString(), isNot(contains('push.apple.com')));
        return;
      }
      expect(config['rules'].first, contains('push.apple.com'));
      expect(config['dns']['respect-rules'], true);
      expect(config['rules'], contains('IP-CIDR,1.1.1.1/32,Exit,no-resolve'));
      final disabled = await _compile(const NetworkProps());
      expect(disabled.yaml, isNot(contains('PROCESS-NAME,apsd')));
      expect(
        loadYaml(disabled.yaml)['tun']['route-exclude-address'],
        contains('17.0.0.0/8'),
      );
      expect(enabled.structureMd5, isNot(disabled.structureMd5));
    },
  );
}
