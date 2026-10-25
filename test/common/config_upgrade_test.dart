import 'dart:convert';

import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/common/config_overrides.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Future<CompiledProfile> _compile(
  PatchClashConfig patch, {
  ProfileSource source = ProfileSource.user,
}) => compileProfileTask(
  MakeRealProfileState(
    profilesPath: '/profiles',
    profileId: 1,
    rawConfig: {
      'ipv6': true,
      'tcp-concurrent': false,
      'tun': {
        'stack': 'gvisor',
        'mtu': 1400,
        'route-exclude-address': ['10.0.0.0/8'],
      },
      'dns': {
        'enable': true,
        'nameserver': ['https://dns.example/dns-query'],
        'cache-max-size': 1000,
      },
      'ntp': {'enable': true, 'server': 'ntp.example', 'port': 123},
      'sniffer': {
        'enable': true,
        'skip-domain': ['+.example'],
      },
      'proxy-groups': [
        {
          'name': 'Exit',
          'type': 'select',
          'proxies': ['DIRECT'],
        },
      ],
      'rules': ['MATCH,Exit'],
    },
    realPatchConfig: patch,
    profileSource: source,
    overrideDns: true,
    appendSystemDns: false,
    proxyGroups: const [],
    rules: const [],
    addedRules: const [],
    defaultUA: 'test',
  ),
);

void main() {
  test(
    'provider-backed DNS and sniffer changes retain the full-apply path',
    () {
      expect(
        supportsRuntimeConfig({
          'dns': {
            'nameserver': ['https://1.1.1.1/dns-query'],
          },
        }),
        true,
      );
      expect(
        supportsRuntimeConfig({
          'dns': {
            'nameserver-policy': {'rule-set:local': '1.1.1.1'},
          },
        }),
        false,
      );
      expect(
        supportsRuntimeConfig({
          'sniffer': {
            'skip-domain': ['rule-set:local'],
          },
        }),
        false,
      );
    },
  );

  test(
    'old settings preserve their override semantics after round trip',
    () async {
      final patch = PatchClashConfig.fromJson(
        jsonDecode(jsonEncode(const PatchClashConfig()))
            as Map<String, dynamic>,
      );
      expect(patch.generalOverrideKeys, isNull);
      expect(patch.dnsOverrideKeys, isNull);
      expect(patch.tunOverrideKeys, isNull);
      final result = loadYaml((await _compile(patch)).yaml);
      expect(result['ipv6'], false);
      expect(result['tcp-concurrent'], true);
      expect(result['dns']['nameserver'], const Dns().nameserver);
      expect(result['tun']['stack'], 'mixed');
      expect(result['ntp']['server'], 'ntp.example');
      expect(result['sniffer']['enable'], true);
    },
  );

  test(
    'only selected fields override subscriptions and empty values apply',
    () async {
      final result = loadYaml(
        (await _compile(
          const PatchClashConfig(
            generalOverrideKeys: {'tcp-concurrent'},
            dnsOverrideKeys: {'cache-max-size'},
            dns: Dns(cacheMaxSize: 8192),
            tunOverrideKeys: {'mtu', 'route-exclude-address'},
            tun: Tun(mtu: 1300, routeExcludeAddress: []),
            ntp: Ntp(interval: 60),
            ntpOverrideKeys: {'interval'},
            sniffer: Sniffer(skipDomain: []),
            snifferOverrideKeys: {'skip-domain'},
          ),
        )).yaml,
      );
      expect(result['ipv6'], true);
      expect(result['tcp-concurrent'], true);
      expect(result['dns']['cache-max-size'], 8192);
      expect(result['dns']['nameserver'], ['https://dns.example/dns-query']);
      expect(result['tun']['stack'], 'gvisor');
      expect(result['tun']['mtu'], 1300);
      expect(result['tun']['route-exclude-address'], isEmpty);
      expect(result['tun']['enable'], false);
      expect(result['tun']['auto-detect-interface'], true);
      expect(result['ntp']['server'], 'ntp.example');
      expect(result['ntp']['interval'], 60);
      expect(result['sniffer']['enable'], true);
      expect(result['sniffer']['skip-domain'], isEmpty);
    },
  );

  test('official DNS policy wins over optional inherited overrides', () async {
    final result = loadYaml(
      (await _compile(
        const PatchClashConfig(dnsOverrideKeys: {}, tunOverrideKeys: {}),
        source: ProfileSource.xboard,
      )).yaml,
    );
    expect(result['dns']['respect-rules'], true);
    expect(result['dns']['nameserver'], [
      'https://1.1.1.1/dns-query#RULES',
      'https://8.8.8.8/dns-query#RULES',
    ]);
    expect(result['tun']['dns-hijack'], ['any:53']);
  });

  test('runtime changes do not alter structural fingerprint', () async {
    final initial = await _compile(const PatchClashConfig());
    final dns = await _compile(
      const PatchClashConfig(
        dns: Dns(cacheMaxSize: 8192),
        hosts: {'local.example': '127.0.0.1'},
      ),
    );
    final changedMode = await _compile(
      const PatchClashConfig(mode: Mode.global),
    );
    expect(dns.md5, isNot(initial.md5));
    expect(dns.structureMd5, initial.structureMd5);
    expect(dns.runtimeConfig['hosts']['local.example'], '127.0.0.1');
    expect(changedMode.structureMd5, isNot(initial.structureMd5));
    expect(
      dns.runtimeConfig.keys,
      unorderedEquals(['dns', 'hosts', 'ntp', 'sniffer']),
    );
  });

  test('new DNS and TUN fields survive backup serialization', () {
    const patch = PatchClashConfig(
      dns: Dns(
        cacheAlgorithm: 'arc',
        cacheMaxSize: 8192,
        directNameserver: ['https://1.1.1.1/dns-query'],
        proxyServerNameserverPolicy: {'+.example': '1.1.1.1'},
      ),
      tun: Tun(stack: TunStack.mips, dnsMode: 'hijack', udpTimeout: 120),
      dnsOverrideKeys: {'cache-algorithm', 'direct-nameserver'},
    );
    final restored = PatchClashConfig.fromJson(
      jsonDecode(jsonEncode(patch)) as Map<String, dynamic>,
    );
    expect(restored, patch);
    expect(AppSettingProps.fromJson({'testTimeout': -1}).testTimeout, 100);
    expect(
      AppSettingProps.fromJson({'testTimeout': 999999}).testTimeout,
      120000,
    );
    expect(AppSettingProps.fromJson({}).testTimeout, 5000);
  });
}
