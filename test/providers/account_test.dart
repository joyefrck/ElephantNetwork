import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/account.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  test('successful login returns navigation to the dashboard', () async {
    final container = ProviderContainer(
      overrides: [
        xboardApiProvider.overrideWithValue(
          XboardApi(transport: _LoginTransport()),
        ),
        xboardSessionStoreProvider.overrideWithValue(
          XboardSessionStore(
            secureStore: _MemorySecureStore(),
            legacyStore: _MemoryLegacyStore(),
          ),
        ),
        xboardManagedProfileGatewayProvider.overrideWithValue(
          _NoopManagedProfileGateway(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentPageLabelProvider.notifier).toPage(PageLabel.account);

    final authenticated = await container
        .read(xboardSessionControllerProvider.notifier)
        .login('owner@example.com', 'password');

    expect(authenticated, isTrue);
    expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
  });

  test('managed subscription sync reapplies the current profile', () async {
    final profile =
        Profile.normal(
          label: 'Managed',
          url: 'https://example.com/old',
        ).copyWith(
          source: ProfileSource.xboard,
          ownerAccountId: _account.accountId,
        );
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => _TestProfiles([profile])),
        setupActionProvider.overrideWith(() => _RecordingSetupAction()),
      ],
    );
    addTearDown(container.dispose);
    final gatewayProvider = Provider<XboardManagedProfileGateway>((ref) {
      return RiverpodXboardManagedProfileGateway(
        ref,
        updateProfile: (candidate) async =>
            candidate.copyWith(lastUpdateDate: DateTime(2026)),
        hasNodes: () => true,
      );
    });
    final setupAction =
        container.read(setupActionProvider.notifier) as _RecordingSetupAction;

    var completed = false;
    final reconciliation = container
        .read(gatewayProvider)
        .reconcile(Uri.parse('https://example.com/new'), _account)
        .whenComplete(() => completed = true);

    await setupAction.started.future;
    expect(completed, isFalse);
    setupAction.release.complete();
    await reconciliation;

    final updated = container.read(profilesProvider).single;
    expect(updated.url, 'https://example.com/new');
    expect(setupAction.applyProfileCount, 1);
  });

  test(
    'managed subscription sync replaces an active third-party profile',
    () async {
      final userProfile = Profile.normal(label: 'User');
      final managedProfile = Profile.normal(label: 'Managed').copyWith(
        source: ProfileSource.xboard,
        ownerAccountId: _account.accountId,
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => userProfile.id),
          profilesProvider.overrideWith(
            () => _TestProfiles([userProfile, managedProfile]),
          ),
          setupActionProvider.overrideWith(() => _ImmediateSetupAction()),
        ],
      );
      addTearDown(container.dispose);
      final gatewayProvider = Provider<XboardManagedProfileGateway>((ref) {
        return RiverpodXboardManagedProfileGateway(
          ref,
          updateProfile: (candidate) async => candidate,
          hasNodes: () => true,
        );
      });

      await container
          .read(gatewayProvider)
          .reconcile(Uri.parse('https://example.com/new'), _account);

      final setupAction =
          container.read(setupActionProvider.notifier) as _ImmediateSetupAction;
      expect(container.read(currentProfileIdProvider), managedProfile.id);
      expect(setupAction.applyProfileCount, 2);
    },
  );

  test('managed subscription sync rejects an empty applied profile', () async {
    final profile = Profile.normal(label: 'Managed').copyWith(
      source: ProfileSource.xboard,
      ownerAccountId: _account.accountId,
    );
    final container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profilesProvider.overrideWith(() => _TestProfiles([profile])),
        setupActionProvider.overrideWith(() => _ImmediateSetupAction()),
      ],
    );
    addTearDown(container.dispose);
    final gatewayProvider = Provider<XboardManagedProfileGateway>((ref) {
      return RiverpodXboardManagedProfileGateway(
        ref,
        updateProfile: (candidate) async => candidate,
        hasNodes: () => false,
      );
    });

    await expectLater(
      container
          .read(gatewayProvider)
          .reconcile(Uri.parse('https://example.com/new'), _account),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'managed_profile_has_no_nodes',
        ),
      ),
    );
  });

  for (final source in [ProfileSource.user, ProfileSource.xboard]) {
    test(
      'failed download cannot leave a foreign $source profile active',
      () async {
        final foreign = Profile.normal(
          label: 'Foreign',
        ).copyWith(source: source, ownerAccountId: 'other@example.com');
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => foreign.id),
            profilesProvider.overrideWith(() => _TestProfiles([foreign])),
            setupActionProvider.overrideWith(() => _ImmediateSetupAction()),
          ],
        );
        addTearDown(container.dispose);
        container.read(groupsProvider.notifier).value = [
          const Group(name: 'Foreign nodes', type: GroupType.Selector),
        ];
        final gatewayProvider = Provider<XboardManagedProfileGateway>((ref) {
          return RiverpodXboardManagedProfileGateway(
            ref,
            updateProfile: (_) async {
              expect(ref.read(currentProfileIdProvider), isNull);
              expect(ref.read(groupsProvider), isEmpty);
              throw StateError('download_failed');
            },
          );
        });

        await expectLater(
          container
              .read(gatewayProvider)
              .reconcile(Uri.parse('https://example.com/new'), _account),
          throwsA(isA<StateError>()),
        );

        final setup =
            container.read(setupActionProvider.notifier)
                as _ImmediateSetupAction;
        expect(setup.runningRequests, [false]);
        expect(setup.appliedProfileIds, [null]);
        expect(container.read(currentProfileIdProvider), isNull);
        expect(container.read(groupsProvider), isEmpty);
        expect(container.read(profilesProvider), [foreign]);
      },
    );
  }

  test(
    'old displayed groups cannot make a failed apply look successful',
    () async {
      final profile = Profile.normal(label: 'Managed').copyWith(
        source: ProfileSource.xboard,
        ownerAccountId: _account.accountId,
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          setupActionProvider.overrideWith(() => _ImmediateSetupAction()),
        ],
      );
      addTearDown(container.dispose);
      container.read(groupsProvider.notifier).value = [
        const Group(name: 'Stale nodes', type: GroupType.Selector),
      ];
      final gatewayProvider = Provider<XboardManagedProfileGateway>((ref) {
        return RiverpodXboardManagedProfileGateway(
          ref,
          updateProfile: (candidate) async => candidate,
        );
      });

      await expectLater(
        container
            .read(gatewayProvider)
            .reconcile(Uri.parse('https://example.com/new'), _account),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'managed_profile_has_no_nodes',
          ),
        ),
      );
      expect(container.read(groupsProvider), isEmpty);
    },
  );
}

const _account = XboardAccount(
  email: 'owner@example.com',
  balance: 0,
  upload: 0,
  download: 0,
  planTransferEnable: 0,
  planUsedTraffic: 0,
  planRemainingTraffic: 0,
  trafficPackageTotal: 0,
  trafficPackageRemaining: 0,
  effectiveTransferEnable: 0,
  effectiveRemainingTraffic: 0,
);

class _TestProfiles extends Profiles {
  _TestProfiles(this.initial);

  final List<Profile> initial;

  @override
  List<Profile> build() => initial;

  @override
  void put(Profile profile) {
    final exists = state.any((item) => item.id == profile.id);
    state = exists
        ? [
            for (final item in state)
              if (item.id == profile.id) profile else item,
          ]
        : [...state, profile];
  }
}

class _RecordingSetupAction extends SetupAction {
  int applyProfileCount = 0;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyProfileCount++;
    started.complete();
    await release.future;
  }
}

class _ImmediateSetupAction extends SetupAction {
  int applyProfileCount = 0;
  final runningRequests = <bool>[];
  final appliedProfileIds = <int?>[];

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    runningRequests.add(running);
  }

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyProfileCount++;
    appliedProfileIds.add(ref.read(currentProfileIdProvider));
  }
}

class _LoginTransport implements XboardTransport {
  @override
  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? data,
  }) async {
    return switch (path) {
      XboardConfig.loginPath => {
        'status': 'success',
        'data': {'auth_data': 'token'},
      },
      XboardConfig.userInfoPath => {
        'data': {'email': 'owner@example.com'},
      },
      _ => throw StateError('unexpected_path'),
    };
  }
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _MemoryLegacyStore implements LegacyTokenStore {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => null;
}

class _NoopManagedProfileGateway implements XboardManagedProfileGateway {
  @override
  Future<void> prepare(XboardAccount account) async {}

  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) async {}

  @override
  Future<void> stopAndRemove() async {}
}
