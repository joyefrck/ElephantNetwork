import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

class _RuntimeSetupAction extends SetupAction {
  CompiledProfile compiled = (
    yaml: 'dns: {enable: true}',
    md5: 'accepted',
    structureMd5: 'unchanged-groups',
    runtimeConfig: {
      'dns': {'enable': true},
    },
  );
  String rejection = '';
  int runtimeCalls = 0;
  final written = <String>[];

  @override
  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    void Function(CompiledProfile)? onCompiled,
  }) async {
    onCompiled?.call(compiled);
    return VM2(compiled.yaml, compiled.md5);
  }

  @override
  Future<String> applyRuntimeSections(Map<String, dynamic> config) async {
    runtimeCalls++;
    return rejection;
  }

  @override
  Future<void> writeRuntimeProfile(String yaml, String md5) async {
    written.add(md5);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed hot updates keep the accepted digest and allow a later retry',
    () async {
      final previous = globalState.lastConfigMd5;
      globalState.lastConfigMd5 = 'accepted';
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(_RuntimeSetupAction.new),
          setupStateProvider(null).overrideWith(
            (_) async => const SetupState(
              profileId: null,
              profileLastUpdateDate: null,
              overwriteType: OverwriteType.standard,
              rules: [],
              proxyGroups: [],
              addedRules: [],
              script: null,
              overrideDns: false,
              dns: Dns(),
            ),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        globalState.lastConfigMd5 = previous;
      });
      final action =
          container.read(setupActionProvider.notifier) as _RuntimeSetupAction;
      await action.applyProfile();
      expect(action.runtimeCalls, 0);
      action.compiled = (
        yaml: 'dns: {enable: true, cache-max-size: 8192}',
        md5: 'new-dns',
        structureMd5: 'unchanged-groups',
        runtimeConfig: {
          'dns': {'enable': true, 'cache-max-size': 8192},
        },
      );
      action.rejection = 'invalid DNS';
      await action.applyProfile();
      expect(globalState.lastConfigMd5, 'accepted');
      expect(action.written, isEmpty);
      action.rejection = '';
      await action.applyProfile();
      expect(globalState.lastConfigMd5, 'new-dns');
      expect(action.written, ['new-dns']);
      expect(action.runtimeCalls, 2);
    },
  );
}
