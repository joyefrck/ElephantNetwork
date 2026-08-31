import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/features/account/xboard_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'action.dart';
import 'config.dart';
import 'database.dart';

part 'generated/account.g.dart';

@Riverpod(keepAlive: true)
XboardApi xboardApi(Ref ref) => XboardApi();

@Riverpod(keepAlive: true)
XboardSessionStore xboardSessionStore(Ref ref) => XboardSessionStore();

@Riverpod(keepAlive: true)
XboardManagedProfileGateway xboardManagedProfileGateway(Ref ref) {
  return RiverpodXboardManagedProfileGateway(ref);
}

@Riverpod(keepAlive: true)
class XboardSessionController extends _$XboardSessionController {
  late final XboardSessionCoordinator _coordinator;

  @override
  XboardSessionState build() {
    _coordinator = XboardSessionCoordinator(
      api: ref.read(xboardApiProvider),
      store: ref.read(xboardSessionStoreProvider),
      managedProfile: ref.read(xboardManagedProfileGatewayProvider),
      onChanged: (value) => state = value,
    );
    return _coordinator.state;
  }

  Future<bool> restore() => _coordinator.restore();

  Future<bool> login(String email, String password) {
    return _coordinator.login(email, password);
  }

  Future<bool> refresh() => _coordinator.refresh();

  Future<bool> syncManagedProfile() => _coordinator.syncManagedProfile();

  Future<void> logout() => _coordinator.logout();
}

class RiverpodXboardManagedProfileGateway
    implements XboardManagedProfileGateway {
  RiverpodXboardManagedProfileGateway(this.ref);

  final Ref ref;

  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) async {
    final profiles = ref.read(profilesProvider);
    final managedProfiles = profiles
        .where((profile) => profile.source == ProfileSource.xboard)
        .toList();
    final existing = managedProfiles.firstOrNull;
    final candidate = buildXboardManagedProfile(
      existing: existing,
      subscription: subscription,
      account: account,
    );
    final updated = await candidate.update();
    ref.read(profilesActionProvider.notifier).putProfile(updated);
    for (final stale in managedProfiles.skip(1)) {
      await ref.read(profilesActionProvider.notifier).deleteProfile(stale.id);
    }
    final currentId = ref.read(currentProfileIdProvider);
    final current = profiles.getProfile(currentId);
    if (current == null || current.source == ProfileSource.xboard) {
      ref.read(currentProfileIdProvider.notifier).value = updated.id;
    }
  }

  @override
  Future<void> stopAndRemove() async {
    final profiles = ref.read(profilesProvider);
    final managedProfiles = profiles
        .where((profile) => profile.source == ProfileSource.xboard)
        .toList();
    final currentId = ref.read(currentProfileIdProvider);
    if (managedProfiles.any((profile) => profile.id == currentId)) {
      await ref.read(setupActionProvider.notifier).setRunning(false);
    }
    for (final profile in managedProfiles) {
      await ref.read(profilesActionProvider.notifier).deleteProfile(profile.id);
    }
  }
}
