import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/features/account/xboard_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'action.dart';
import 'app.dart';
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

  Future<bool> login(String email, String password) async {
    final authenticated = await _coordinator.login(email, password);
    if (authenticated) {
      ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.dashboard);
    }
    return authenticated;
  }

  Future<bool> refresh() => _coordinator.refresh();

  Future<bool> syncManagedProfile({int maxRetries = 0}) {
    return _coordinator.syncManagedProfile(maxRetries: maxRetries);
  }

  Future<void> logout() => _coordinator.logout();
}

class RiverpodXboardManagedProfileGateway
    implements XboardManagedProfileGateway {
  RiverpodXboardManagedProfileGateway(
    this.ref, {
    Future<Profile> Function(Profile profile)? updateProfile,
    bool Function()? hasNodes,
  }) : _updateProfile = updateProfile ?? ((profile) => profile.update()),
       _hasNodes = hasNodes ?? (() => ref.read(groupsProvider).isNotEmpty);

  final Ref ref;
  final Future<Profile> Function(Profile profile) _updateProfile;
  final bool Function() _hasNodes;

  @override
  Future<void> prepare(XboardAccount account) async {
    final currentId = ref.read(currentProfileIdProvider);
    final current = ref.read(profilesProvider).getProfile(currentId);
    if (isXboardProfileForAccount(current, account.accountId)) {
      return;
    }
    ref.read(currentProfileIdProvider.notifier).value = null;
    _clearNodes();
    final setup = ref.read(setupActionProvider.notifier);
    try {
      await setup.setRunning(false);
      await setup.applyProfile(silence: true, force: true);
    } finally {
      _clearNodes();
    }
  }

  void _clearNodes() {
    ref.read(groupsProvider.notifier).value = [];
    ref.read(providersProvider.notifier).value = [];
    ref.read(delayDataSourceProvider.notifier).value = {};
  }

  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) async {
    await prepare(account);
    final profiles = ref.read(profilesProvider);
    final managedProfiles = profiles
        .where((profile) => profile.source == ProfileSource.xboard)
        .toList();
    final existing = managedProfiles
        .where((profile) => profile.ownerAccountId == account.accountId)
        .firstOrNull;
    final candidate = buildXboardManagedProfile(
      existing: existing,
      subscription: subscription,
      account: account,
    );
    final updated = await _updateProfile(candidate);
    ref.read(profilesActionProvider.notifier).putProfile(updated);
    ref.read(currentProfileIdProvider.notifier).value = updated.id;
    for (final stale in managedProfiles.where(
      (profile) => profile.id != updated.id,
    )) {
      await ref.read(profilesActionProvider.notifier).deleteProfile(stale.id);
    }
    _clearNodes();
    await ref
        .read(setupActionProvider.notifier)
        .applyProfile(silence: true, force: true);
    if (!_hasNodes()) throw StateError('managed_profile_has_no_nodes');
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
