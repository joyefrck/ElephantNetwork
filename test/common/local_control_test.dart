import 'dart:convert';

import 'package:fl_clash/common/local_control.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const enabled = Config(
    themeProps: ThemeProps(),
    patchClashConfig: PatchClashConfig(
      externalController: ExternalControllerStatus.open,
    ),
    networkProps: NetworkProps(
      authentication: AuthenticationProps(enable: true),
    ),
  );

  test(
    'old settings and restored settings gain persistent valid credentials',
    () {
      final first = normalizeLocalControlConfig(enabled);
      expect(first.patchClashConfig.secret, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(first.networkProps.authentication.isValid, true);
      final restored = Config.fromJson(jsonDecode(jsonEncode(first)));
      expect(normalizeLocalControlConfig(restored), first);
      expect(
        normalizeLocalControlConfig(enabled).patchClashConfig.secret,
        isNot(first.patchClashConfig.secret),
      );
      const closed = Config(themeProps: ThemeProps());
      expect(normalizeLocalControlConfig(closed), closed);
      expect(closed.networkProps.authentication.credentials, isEmpty);
    },
  );

  test('invalid enabled proxy credentials fail closed', () {
    for (final auth in [
      const AuthenticationProps(enable: true),
      const AuthenticationProps(
        enable: true,
        username: 'a:b',
        password: 'test',
      ),
      const AuthenticationProps(
        enable: true,
        username: 'a b',
        password: 'test',
      ),
      const AuthenticationProps(enable: true, username: 'user', password: '\n'),
    ]) {
      expect(() => auth.credentials, throwsStateError);
      expect(auth.ensureCredentials().credentials, hasLength(1));
    }
    expect(
      const AuthenticationProps(
        enable: true,
        username: 'user',
        password: 'a:b',
      ).credentials,
      ['user:a:b'],
    );
  });

  for (final safe in [false, true]) {
    test(
      'profile compilation owns control and authentication endpoints safe=$safe',
      () async {
        final patch = normalizeLocalControlConfig(enabled).patchClashConfig;
        final compiled = await compileProfileTask(
          MakeRealProfileState(
            profilesPath: '/profiles',
            profileId: 1,
            rawConfig: {
              'external-controller': '0.0.0.0:9000',
              'external-controller-tls': '0.0.0.0:9001',
              'external-controller-unix': '/tmp/foreign.sock',
              'external-controller-pipe': 'foreign',
              'external-ui': 'foreign',
              'secret': 'foreign',
              'authentication': ['foreign:foreign'],
              'skip-auth-prefixes': ['127.0.0.0/8'],
              'rules': ['MATCH,DIRECT'],
            },
            realPatchConfig: patch,
            overrideDns: false,
            appendSystemDns: false,
            authentication: const ['local:test:pass'],
            safeMode: safe,
            proxyGroups: const [],
            rules: const [],
            addedRules: const [],
            defaultUA: 'test',
          ),
        );
        final config = loadYaml(compiled.yaml);
        expect(config['external-controller'], safe ? '' : '127.0.0.1:9090');
        expect(config['secret'], patch.secret);
        for (final endpoint in ['tls', 'unix', 'pipe']) {
          expect(config['external-controller-$endpoint'], '');
        }
        expect(config['external-ui'], '');
        expect(config['authentication'], ['local:test:pass']);
        expect(config['skip-auth-prefixes'], isEmpty);
        expect(config['mixed-port'], patch.mixedPort);
        expect(config['rules'], ['MATCH,DIRECT']);
      },
    );
  }

  test('missing or unsafe secret cannot open a controller', () {
    for (final secret in ['', 'short', '${'a' * 32}\n']) {
      expect(
        effectiveController(enabled.patchClashConfig.copyWith(secret: secret)),
        ExternalControllerStatus.close,
      );
    }
  });
}
