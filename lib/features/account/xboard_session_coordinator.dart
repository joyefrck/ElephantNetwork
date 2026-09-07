import 'dart:async';

import 'xboard_api.dart';
import 'xboard_models.dart';
import 'xboard_session_store.dart';

abstract interface class XboardManagedProfileGateway {
  Future<void> reconcile(Uri subscription, XboardAccount account);

  Future<void> stopAndRemove();
}

class XboardSessionCoordinator {
  XboardSessionCoordinator({
    required XboardApi api,
    required XboardSessionStore store,
    required XboardManagedProfileGateway managedProfile,
    void Function(XboardSessionState state)? onChanged,
    Future<void> Function(Duration delay)? retryDelay,
  }) : _api = api,
       _store = store,
       _managedProfile = managedProfile,
       _onChanged = onChanged,
       _retryDelay = retryDelay ?? Future<void>.delayed;

  static const _managedProfileRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final XboardApi _api;
  final XboardSessionStore _store;
  final XboardManagedProfileGateway _managedProfile;
  final void Function(XboardSessionState state)? _onChanged;
  final Future<void> Function(Duration delay) _retryDelay;
  Future<void> _pending = Future.value();

  XboardSessionState state = const XboardSessionState.loading();

  Future<bool> restore() => _serialized(_restore);

  Future<bool> _restore() async {
    _setState(const XboardSessionState.loading());
    String? token;
    try {
      final email = await _store.readEmail();
      _setState(XboardSessionState.loading(email: email));
      token = await _store.readToken();
    } catch (_) {
      _setState(const XboardSessionState.unauthenticated());
      return false;
    }
    if (token == null || token.isEmpty) {
      _setState(const XboardSessionState.unauthenticated());
      return false;
    }
    return _activate(token, persist: false, exposeFailure: false);
  }

  Future<bool> login(String email, String password) {
    return _serialized(() => _login(email, password));
  }

  Future<bool> _login(String email, String password) async {
    _setState(XboardSessionState.authenticating(email.trim()));
    try {
      final token = await _api.login(email, password);
      return await _activate(token, persist: true);
    } catch (error) {
      _setState(XboardSessionState.unauthenticated(error));
      return false;
    }
  }

  Future<bool> refresh() => _serialized(_refresh);

  Future<bool> _refresh() async {
    final session = state.session;
    if (session == null) return false;
    return _activate(session.token, persist: false, keepSessionOnFailure: true);
  }

  Future<bool> syncManagedProfile({int maxRetries = 0}) {
    return _serialized(
      () => _syncManagedProfile(maxRetries: maxRetries.clamp(0, 3)),
    );
  }

  Future<bool> _syncManagedProfile({required int maxRetries}) async {
    final session = state.session;
    if (session == null) return false;
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final subscription = await _api.managedSubscription(session.token);
        await _managedProfile
            .reconcile(subscription, session.account)
            .timeout(const Duration(seconds: 30));
        _setState(XboardSessionState.authenticated(session));
        return true;
      } catch (error) {
        lastError = error;
        if (attempt == maxRetries || !_isRetryableProfileError(error)) break;
        await _retryDelay(_managedProfileRetryDelays[attempt]);
      }
    }
    _setState(XboardSessionState.authenticated(session, error: lastError));
    return false;
  }

  bool _isRetryableProfileError(Object error) {
    if (error is! XboardApiException) return true;
    final statusCode = error.statusCode;
    if (statusCode != null) return statusCode >= 500;
    return !const {
      'missing_subscribe_url',
      'invalid_subscribe_url',
    }.contains(error.message);
  }

  Future<void> logout() => _serialized(_logout);

  Future<void> _logout() async {
    Object? failure;
    try {
      await _managedProfile.stopAndRemove();
    } catch (error) {
      failure = error;
    }
    try {
      await _store.clear();
    } catch (error) {
      failure ??= error;
    }
    _setState(XboardSessionState.unauthenticated(failure));
  }

  Future<bool> _activate(
    String token, {
    required bool persist,
    bool keepSessionOnFailure = false,
    bool exposeFailure = true,
  }) async {
    try {
      final account = await _api.account(token);
      if (persist) {
        await _store.saveSession(token, account.email);
      }
      _setState(
        XboardSessionState.authenticated(
          XboardSession(token: token, account: account),
        ),
      );
      return true;
    } on XboardApiException catch (error) {
      if (error.isUnauthorized) {
        await _managedProfile.stopAndRemove();
        await _store.clear();
        _setState(
          XboardSessionState.unauthenticated(exposeFailure ? error : null),
        );
        return false;
      }
      if (keepSessionOnFailure && state.session != null) {
        _setState(
          XboardSessionState.authenticated(state.session, error: error),
        );
      } else if (exposeFailure) {
        _setState(XboardSessionState.unavailable(error));
      } else {
        _setState(const XboardSessionState.unauthenticated());
      }
      return false;
    } catch (error) {
      if (keepSessionOnFailure && state.session != null) {
        _setState(
          XboardSessionState.authenticated(state.session, error: error),
        );
      } else if (exposeFailure) {
        _setState(XboardSessionState.unavailable(error));
      } else {
        _setState(const XboardSessionState.unauthenticated());
      }
      return false;
    }
  }

  void _setState(XboardSessionState value) {
    state = value;
    _onChanged?.call(value);
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
