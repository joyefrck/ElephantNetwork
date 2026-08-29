import 'dart:async';

import 'package:fl_clash/features/account/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XboardApi', () {
    test('logs in and requests account with bearer token', () async {
      final transport = _FakeTransport({
        XboardConfig.loginPath: {
          'status': 'success',
          'data': {'auth_data': 'secret-token'},
        },
        XboardConfig.userInfoPath: {
          'status': 'success',
          'data': {
            'email': 'user@example.com',
            'balance': 1234,
            'u': 100,
            'd': 200,
            'transfer_enable': 1000,
            'plan_transfer_enable': 800,
            'traffic_package_remaining': 100,
            'effective_transfer_enable': 900,
          },
        },
      });
      final api = XboardApi(transport: transport);

      final token = await api.login(' user@example.com ', 'password');
      final account = await api.account(token);

      expect(token, 'secret-token');
      expect(account.accountId, 'user@example.com');
      expect(account.planUsedTraffic, 300);
      expect(account.planRemainingTraffic, 500);
      expect(account.effectiveRemainingTraffic, 600);
      expect(transport.requests[0].data, {
        'email': 'user@example.com',
        'password': 'password',
      });
      expect(transport.requests[1].token, 'secret-token');
    });

    test('managed subscription always requests the FlClash renderer', () async {
      final api = XboardApi(
        transport: _FakeTransport({
          XboardConfig.subscribeInfoPath: {
            'data': {
              'subscribe_url':
                  'https://example.com/api/v1/client/subscribe?token=secret',
            },
          },
        }),
      );

      final uri = await api.managedSubscription('auth-token');

      expect(uri.queryParameters['token'], 'secret');
      expect(uri.queryParameters['flag'], 'flclash');
    });

    test('managed subscription rejects an insecure URL', () async {
      final api = XboardApi(
        transport: _FakeTransport({
          XboardConfig.subscribeInfoPath: {
            'data': {
              'subscribe_url': 'http://example.com/subscribe?token=secret',
            },
          },
        }),
      );

      await expectLater(
        api.managedSubscription('auth-token'),
        throwsA(isA<XboardApiException>()),
      );
    });

    test('quick-login URL must be HTTPS', () async {
      final api = XboardApi(
        transport: _FakeTransport({
          XboardConfig.quickLoginPath: {'data': 'http://example.com/app#/plan'},
        }),
      );

      await expectLater(
        api.quickLogin('token', '/app#/plan'),
        throwsA(isA<XboardApiException>()),
      );
    });
  });

  test('redaction removes secrets and sensitive URLs', () {
    final result = XboardRedaction.text(
      'Authorization: Bearer abc token=def password=hello '
      'https://example.com/api/v1/client/subscribe?token=ghi',
    );

    expect(result, isNot(contains('abc')));
    expect(result, isNot(contains('def')));
    expect(result, isNot(contains('hello')));
    expect(result, isNot(contains('ghi')));
    expect(result, contains('[REDACTED]'));
  });

  test('secure URI resolves signed relative update URLs', () {
    final uri = XboardConfig.secureUri(
      '/api/v1/app-downloads/12/download?signature=abc',
      baseUrl: 'https://www.elephant111.org',
    );

    expect(
      uri.toString(),
      'https://www.elephant111.org/api/v1/app-downloads/12/download?signature=abc',
    );
    expect(
      XboardConfig.secureUri(
        'http://example.com/update.apk',
        baseUrl: 'https://www.elephant111.org',
      ),
      isNull,
    );
  });

  group('XboardSessionStore', () {
    test('migrates and deletes a legacy plaintext token', () async {
      final secure = _MemorySecureStore();
      final legacy = _MemoryLegacyStore('legacy-token');
      final store = XboardSessionStore(
        secureStore: secure,
        legacyStore: legacy,
      );

      expect(await store.readToken(), 'legacy-token');
      expect(secure.values.values.single, 'legacy-token');
      expect(legacy.token, isNull);
    });

    test('clears both secure and legacy token locations', () async {
      final secure = _MemorySecureStore();
      final legacy = _MemoryLegacyStore('legacy-token');
      final store = XboardSessionStore(
        secureStore: secure,
        legacyStore: legacy,
      );
      await store.saveToken('secure-token');

      await store.clear();

      expect(secure.values, isEmpty);
      expect(legacy.token, isNull);
    });
  });

  group('XboardSessionCoordinator', () {
    test('login completes before managed profile reconciliation', () async {
      final gateway = _BlockingManagedProfileGateway();
      addTearDown(() {
        if (!gateway.release.isCompleted) gateway.release.complete();
      });
      final coordinator = XboardSessionCoordinator(
        api: XboardApi(
          transport: _FakeTransport({
            XboardConfig.loginPath: {
              'status': 'success',
              'data': {'auth_data': 'token'},
            },
            XboardConfig.userInfoPath: {
              'data': {'email': 'owner@example.com'},
            },
            XboardConfig.subscribeInfoPath: {
              'data': {
                'subscribe_url':
                    'https://example.com/subscribe?token=profile-token',
              },
            },
          }),
        ),
        store: XboardSessionStore(
          secureStore: _MemorySecureStore(),
          legacyStore: _MemoryLegacyStore(null),
        ),
        managedProfile: gateway,
      );

      expect(
        await coordinator
            .login('owner@example.com', 'password')
            .timeout(const Duration(milliseconds: 200)),
        isTrue,
      );
      expect(coordinator.state.isAuthenticated, isTrue);
      expect(gateway.started.isCompleted, isFalse);
    });

    test('managed profile synchronization runs after authentication', () async {
      final gateway = _FakeManagedProfileGateway();
      final coordinator = _authenticatedCoordinator(gateway);

      expect(await coordinator.login('owner@example.com', 'password'), isTrue);
      expect(gateway.subscription, isNull);

      expect(await coordinator.syncManagedProfile(), isTrue);
      expect(gateway.account?.accountId, 'owner@example.com');
      expect(gateway.subscription?.queryParameters['flag'], 'flclash');
    });

    test(
      'managed profile failure preserves the authenticated session',
      () async {
        final coordinator = _authenticatedCoordinator(
          _ThrowingManagedProfileGateway(),
        );

        expect(
          await coordinator.login('owner@example.com', 'password'),
          isTrue,
        );
        expect(await coordinator.syncManagedProfile(), isFalse);
        expect(coordinator.state.isAuthenticated, isTrue);
        expect(coordinator.state.error, isA<StateError>());
      },
    );

    test('restores account before reconciling the managed profile', () async {
      final secure = _MemorySecureStore();
      final store = XboardSessionStore(
        secureStore: secure,
        legacyStore: _MemoryLegacyStore(null),
      );
      await store.saveToken('stored-token');
      final gateway = _FakeManagedProfileGateway();
      final coordinator = XboardSessionCoordinator(
        api: XboardApi(
          transport: _FakeTransport({
            XboardConfig.userInfoPath: {
              'data': {'email': 'owner@example.com'},
            },
            XboardConfig.subscribeInfoPath: {
              'data': {
                'subscribe_url':
                    'https://example.com/subscribe?token=profile-token',
              },
            },
          }),
        ),
        store: store,
        managedProfile: gateway,
      );

      expect(await coordinator.restore(), isTrue);
      expect(coordinator.state.isAuthenticated, isTrue);
      expect(gateway.account, isNull);

      expect(await coordinator.syncManagedProfile(), isTrue);
      expect(gateway.account?.accountId, 'owner@example.com');
      expect(gateway.subscription?.queryParameters['flag'], 'flclash');
    });

    test('secure storage failure keeps the login gate unavailable', () async {
      final coordinator = XboardSessionCoordinator(
        api: XboardApi(transport: _FakeTransport(const {})),
        store: XboardSessionStore(
          secureStore: _ThrowingSecureStore(),
          legacyStore: _MemoryLegacyStore(null),
        ),
        managedProfile: _FakeManagedProfileGateway(),
      );

      expect(await coordinator.restore(), isFalse);
      expect(coordinator.state.status, XboardSessionStatus.unavailable);
    });

    test('unauthorized refresh clears session and managed profile', () async {
      final secure = _MemorySecureStore();
      final store = XboardSessionStore(
        secureStore: secure,
        legacyStore: _MemoryLegacyStore(null),
      );
      await store.saveToken('stored-token');
      final gateway = _FakeManagedProfileGateway();
      final coordinator = XboardSessionCoordinator(
        api: XboardApi(
          transport: _FakeTransport({
            XboardConfig.userInfoPath: const XboardApiException(
              statusCode: 401,
            ),
          }),
        ),
        store: store,
        managedProfile: gateway,
      );

      expect(await coordinator.restore(), isFalse);
      expect(coordinator.state.status, XboardSessionStatus.unauthenticated);
      expect(gateway.removed, isTrue);
      expect(secure.values, isEmpty);
    });

    test(
      'logout waits for an in-flight profile sync and remains final',
      () async {
        final secure = _MemorySecureStore();
        final store = XboardSessionStore(
          secureStore: secure,
          legacyStore: _MemoryLegacyStore(null),
        );
        await store.saveToken('stored-token');
        final gateway = _BlockingManagedProfileGateway();
        final coordinator = XboardSessionCoordinator(
          api: XboardApi(
            transport: _FakeTransport({
              XboardConfig.userInfoPath: {
                'data': {'email': 'owner@example.com'},
              },
              XboardConfig.subscribeInfoPath: {
                'data': {
                  'subscribe_url':
                      'https://example.com/subscribe?token=profile-token',
                },
              },
            }),
          ),
          store: store,
          managedProfile: gateway,
        );

        expect(await coordinator.restore(), isTrue);
        final sync = coordinator.syncManagedProfile();
        await gateway.started.future;
        final logout = coordinator.logout();
        await Future<void>.delayed(Duration.zero);
        expect(gateway.removed, isFalse);
        gateway.release.complete();

        expect(await sync, isTrue);
        await logout;
        expect(coordinator.state.status, XboardSessionStatus.unauthenticated);
        expect(gateway.removed, isTrue);
        expect(secure.values, isEmpty);
      },
    );
  });

  group('XboardDomainResolver', () {
    test('selects the highest-weight healthy HTTPS candidate', () async {
      final store = _MemoryDomainStore();
      final transport = _FakeDomainTransport(
        config: {
          'domains': [
            {'url': 'https://low.example.com', 'weight': 1, 'enabled': true},
            {'url': 'https://high.example.com/', 'weight': 10, 'enabled': true},
            {
              'url': 'http://unsafe.example.com',
              'weight': 100,
              'enabled': true,
            },
          ],
        },
        healthyHosts: {'low.example.com', 'high.example.com'},
      );
      final resolver = XboardDomainResolver(transport: transport, store: store);

      expect(await resolver.resolve(), 'https://high.example.com');
      expect(store.value, 'https://high.example.com');
      expect(
        transport.probed.map((uri) => uri.host),
        isNot(contains('unsafe.example.com')),
      );
    });

    test('falls back to the cached HTTPS domain', () async {
      final store = _MemoryDomainStore('https://cached.example.com');
      final resolver = XboardDomainResolver(
        transport: _FakeDomainTransport(
          config: const {},
          healthyHosts: const {},
        ),
        store: store,
      );

      expect(await resolver.resolve(), 'https://cached.example.com');
    });
  });
}

class _Request {
  const _Request({required this.path, this.token, this.data});

  final String path;
  final String? token;
  final Map<String, Object?>? data;
}

class _FakeTransport implements XboardTransport {
  _FakeTransport(this.responses);

  final Map<String, Object?> responses;
  final List<_Request> requests = [];

  @override
  Future<Object?> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? data,
  }) async {
    requests.add(_Request(path: path, token: token, data: data));
    final response = responses[path];
    if (response is Exception) throw response;
    return response;
  }
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

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

class _ThrowingSecureStore implements SecureKeyValueStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) {
    throw StateError('secure_storage_unavailable');
  }

  @override
  Future<void> write(String key, String value) async {}
}

class _MemoryLegacyStore implements LegacyTokenStore {
  _MemoryLegacyStore(this.token);

  String? token;

  @override
  Future<void> deleteToken() async {
    token = null;
  }

  @override
  Future<String?> readToken() async => token;
}

class _FakeManagedProfileGateway implements XboardManagedProfileGateway {
  Uri? subscription;
  XboardAccount? account;
  bool removed = false;

  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) async {
    this.subscription = subscription;
    this.account = account;
  }

  @override
  Future<void> stopAndRemove() async {
    removed = true;
  }
}

XboardSessionCoordinator _authenticatedCoordinator(
  XboardManagedProfileGateway gateway,
) {
  return XboardSessionCoordinator(
    api: XboardApi(
      transport: _FakeTransport({
        XboardConfig.loginPath: {
          'status': 'success',
          'data': {'auth_data': 'token'},
        },
        XboardConfig.userInfoPath: {
          'data': {'email': 'owner@example.com'},
        },
        XboardConfig.subscribeInfoPath: {
          'data': {
            'subscribe_url':
                'https://example.com/subscribe?token=profile-token',
          },
        },
      }),
    ),
    store: XboardSessionStore(
      secureStore: _MemorySecureStore(),
      legacyStore: _MemoryLegacyStore(null),
    ),
    managedProfile: gateway,
  );
}

class _ThrowingManagedProfileGateway extends _FakeManagedProfileGateway {
  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) {
    throw StateError('managed_profile_sync_failed');
  }
}

class _BlockingManagedProfileGateway extends _FakeManagedProfileGateway {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> reconcile(Uri subscription, XboardAccount account) async {
    started.complete();
    await release.future;
    await super.reconcile(subscription, account);
  }
}

class _MemoryDomainStore implements XboardDomainStore {
  _MemoryDomainStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _FakeDomainTransport implements XboardDomainTransport {
  _FakeDomainTransport({required this.config, required this.healthyHosts});

  final Object? config;
  final Set<String> healthyHosts;
  final List<Uri> probed = [];

  @override
  Future<Object?> fetchConfig(Uri uri) async => config;

  @override
  Future<bool> probe(Uri uri) async {
    probed.add(uri);
    return healthyHosts.contains(uri.host);
  }
}
