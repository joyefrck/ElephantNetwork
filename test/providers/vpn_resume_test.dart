import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResumeSetupAction extends SetupAction {
  final forces = <bool>[];
  final transitions = <bool>[];

  @override
  Future<DateTime?> serviceStartTime() async =>
      DateTime.now().subtract(const Duration(minutes: 1));

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    forces.add(force);
    await preloadInvoke?.call();
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return true;
  }

  @override
  void resetCoreTraffic() {}
}

class _QuietCommonAction extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'adopts a running service using its last accepted configuration',
    () async {
      SharedPreferences.setMockInitialValues({'appliedConfigMd5': 'accepted'});
      await preferences.isInit;
      final previousInit = globalState.needInitStatus;
      final previousMd5 = globalState.lastConfigMd5;
      globalState.needInitStatus = true;
      globalState.lastConfigMd5 = null;
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(_ResumeSetupAction.new),
          commonActionProvider.overrideWith(_QuietCommonAction.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        globalState.needInitStatus = previousInit;
        globalState.lastConfigMd5 = previousMd5;
      });
      final action =
          container.read(setupActionProvider.notifier) as _ResumeSetupAction;
      await action.initStatus();
      expect(action.forces, [false]);
      expect(action.transitions, [true]);
      expect(globalState.lastConfigMd5, 'accepted');
      expect(container.read(isStartProvider), true);
      await action.setRunning(false);
      expect(action.transitions, [true, false]);
    },
  );
}
