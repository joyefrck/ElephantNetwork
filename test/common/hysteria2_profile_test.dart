import 'dart:convert';

import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const node = {
    'name': 'HY2 test',
    'type': 'hysteria2',
    'server': 'node.example.com',
    'port': 443,
    'password': 'fixture-auth',
    'sni': 'node.example.com',
    'obfs': 'salamander',
    'obfs-password': 'fixture-obfs',
    'skip-cert-verify': false,
  };

  for (final source in ProfileSource.values) {
    test('compiled ${source.name} profile retains the HY2 node', () async {
      final compiled = await compileProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 28,
          rawConfig: jsonDecode(
            jsonEncode({
              'proxies': [node],
              'proxy-groups': [
                {
                  'name': 'Exit',
                  'type': 'select',
                  'proxies': [node['name']],
                },
              ],
              'rules': ['MATCH,Exit'],
            }),
          ),
          realPatchConfig: const PatchClashConfig(),
          profileSource: source,
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'ElephantNetwork-Test',
        ),
      );
      final config = loadYaml(compiled.yaml) as YamlMap;

      expect(config['proxies'], [node]);
      expect(config['proxy-groups'][0]['proxies'], [node['name']]);
    });
  }

  for (final sort in ProxiesSortType.values) {
    test('HY2 remains selectable with ${sort.name} sorting', () async {
      final groups = await toGroupsTask(
        ComputeGroupsState(
          proxiesData: ProxiesData.fromJson(
            jsonDecode(
              jsonEncode({
                'all': ['Exit'],
                'proxies': {
                  'Exit': {
                    'type': 'Selector',
                    'name': 'Exit',
                    'now': 'HY2 test',
                    'all': ['VLESS test', 'HY2 test'],
                  },
                  'VLESS test': {'type': 'Vless', 'name': 'VLESS test'},
                  'HY2 test': {'type': 'Hysteria2', 'name': 'HY2 test'},
                },
              }),
            ),
          ),
          sortType: sort,
          delayMap: const {},
          selectedMap: const {'Exit': 'HY2 test'},
          defaultTestUrl: 'https://example.com/generate_204',
        ),
      );

      expect(groups.single.realNow, 'HY2 test');
      expect(
        groups.single.all.singleWhere((proxy) => proxy.name == 'HY2 test').type,
        'Hysteria2',
      );
    });
  }
}
