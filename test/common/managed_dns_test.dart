import 'dart:convert';

import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _subscription({String group = 'Renamed selector'}) => {
  'dns': {
    'enable': true,
    'respect-rules': false,
    'nameserver': ['https://doh.pub/dns-query', 'system://'],
    'fallback': ['https://223.5.5.5/dns-query'],
    'nameserver-policy': {'+.example.com': 'system://'},
  },
  'proxies': [
    {'name': 'US 1', 'type': 'socks5', 'server': '127.0.0.1', 'port': 1080},
    {'name': 'US 2', 'type': 'socks5', 'server': '127.0.0.1', 'port': 1081},
  ],
  'proxy-groups': [
    {
      'name': group,
      'type': 'select',
      'proxies': ['US 1', 'US 2'],
    },
  ],
  'rules': [
    'DOMAIN-SUFFIX,example.cn,DIRECT',
    'GEOIP,CN,DIRECT',
    'MATCH,$group',
  ],
};

Future<YamlMap> _runtime(
  Map<String, dynamic> raw, {
  ProfileSource source = ProfileSource.xboard,
  bool overrideDns = false,
  bool appendSystemDns = false,
  Mode mode = Mode.rule,
}) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 7,
      rawConfig: raw,
      realPatchConfig: PatchClashConfig(mode: mode),
      profileSource: source,
      overrideDns: overrideDns,
      appendSystemDns: appendSystemDns,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'Managed-DNS-Test',
    ),
  );
  return loadYaml(result.a) as YamlMap;
}

void main() {
  for (final overrideDns in [false, true]) {
    for (final appendSystemDns in [false, true]) {
      test(
        'official DNS is protected with legacy override=$overrideDns system=$appendSystemDns',
        () async {
          final config = await _runtime(
            _subscription(),
            overrideDns: overrideDns,
            appendSystemDns: appendSystemDns,
          );
          final dns = config['dns'] as YamlMap;

          expect(dns['enable'], true);
          expect(dns['listen'], '127.0.0.1:1053');
          expect(dns['respect-rules'], true);
          expect(dns['nameserver'], [
            'https://1.1.1.1/dns-query#RULES',
            'https://8.8.8.8/dns-query#RULES',
          ]);
          expect(dns['fallback'], isEmpty);
          expect(dns['nameserver-policy'].keys, ['geosite:cn']);
          expect(dns['nameserver-policy']['geosite:cn'], [
            'https://223.5.5.5/dns-query#RULES',
          ]);
          expect(dns['proxy-server-nameserver'], [
            'https://223.5.5.5/dns-query#DIRECT',
            'https://223.6.6.6/dns-query#DIRECT',
          ]);
          expect(config['rules'].take(2), [
            'IP-CIDR,1.1.1.1/32,Renamed selector,no-resolve',
            'IP-CIDR,8.8.8.8/32,Renamed selector,no-resolve',
          ]);
        },
      );
    }
  }

  test(
    'refresh and restart reapply policy without duplicating DNS routes',
    () async {
      final first = await _runtime(_subscription());
      final restarted = await _runtime(
        jsonDecode(jsonEncode(first)) as Map<String, dynamic>,
      );
      final refreshed = await _runtime(_subscription(group: 'New selector'));

      expect(restarted['dns'], first['dns']);
      expect(restarted['rules'], first['rules']);
      expect(
        refreshed['rules'].first,
        'IP-CIDR,1.1.1.1/32,New selector,no-resolve',
      );
      expect(refreshed['dns'], first['dns']);
    },
  );

  for (final mode in Mode.values) {
    test(
      'DNS follows routing mode ${mode.name} instead of pinning a node',
      () async {
        final config = await _runtime(_subscription(), mode: mode);
        expect(config['mode'], mode.name);
        expect(config['dns']['nameserver'], everyElement(endsWith('#RULES')));
        expect(config['rules'].last, 'MATCH,Renamed selector');
        expect(config['proxy-groups'].single['proxies'], ['US 1', 'US 2']);
      },
    );
  }

  test('ordinary imported profiles retain their DNS and routing', () async {
    final raw = _subscription();
    final config = await _runtime(raw, source: ProfileSource.user);
    expect(config['dns'], raw['dns']);
    expect(config['rules'], raw['rules']);
  });

  test(
    'DNS uses the first effective catch-all instead of an unreachable later one',
    () async {
      final raw = _subscription();
      (raw['proxy-groups'] as List).add({
        'name': 'Earlier selector',
        'type': 'select',
        'proxies': ['US 2'],
      });
      (raw['rules'] as List).insert(0, 'MATCH,Earlier selector');
      final config = await _runtime(raw);
      expect(
        config['rules'].first,
        'IP-CIDR,1.1.1.1/32,Earlier selector,no-resolve',
      );
    },
  );

  test(
    'official profiles fail closed without a usable default proxy',
    () async {
      for (final target in ['DIRECT', 'missing']) {
        final raw = _subscription();
        raw['rules'] = ['MATCH,$target'];
        await expectLater(_runtime(raw), throwsA(isA<StateError>()));
      }
    },
  );
}
