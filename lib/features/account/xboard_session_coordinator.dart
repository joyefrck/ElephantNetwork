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
  }) : _api = api,
       _store = store,
       _managedProfile = managedProfile,
       _onChanged = onChanged;

  final XboardApi _api;
  final XboardSessionStore _store;
  final XboardManagedProfileGateway _managedProfile;
  final void Function(XboardSessionState state)? _onChanged;
  Future<void> _pending = Future.value();

  XboardSessionState state = const XboardSessionState.loading();

  Future<bool> restore() => _serialized(_restore);

  Future<bool> _restore() async {
    _setState(const XboardSessionState.loading());
    String? token;
    try {
      token = await _store.readToken();
    } catch (error) {
      _setState(XboardSessionState.unavailable(error));
      return false;
    }
    if (token == null || token.isEmpty) {
      _setState(const XboardSessionState.unauthenticated());
      return false;
    }
    return _activate(token, persist: false);
  }

  Future<bool> login(String email, String password) {
    return _serialized(() => _login(email, password));
  }

  Future<bool> _login(String email, String password) async {
    _setState(const XboardSessionState.authenticating());
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

  Future<bool> syncManagedProfile() => _serialized(_syncManagedProfile);

  Future<bool> _syncManagedProfile() async {
    final session = state.session;
    if (session == null) return false;
    try {
      final subscription = await _api.managedSubscription(session.token);
      await _managedProfile
          .reconcile(subscription, session.account)
          .timeout(const Duration(seconds: 30));
      _setState(XboardSessionState.authenticated(session));
      return true;
    } catch (error) {
      _setState(XboardSessionState.authenticated(session, error: error));
      return false;
    }
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
  }) async {
    try {
      final account = await _api.account(token);
      if (persist) {
        await _store.saveToken(token);
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
        _setState(XboardSessionState.unauthenticated(error));
        return false;
      }
      if (keepSessionOnFailure && state.session != null) {
        _setState(
          XboardSessionState.authenticated(state.session, error: error),
        );
      } else {
        _setState(XboardSessionState.unavailable(error));
      }
      return false;
    } catch (error) {
      if (keepSessionOnFailure && state.session != null) {
        _setState(
          XboardSessionState.authenticated(state.session, error: error),
        );
      } else {
        _setState(XboardSessionState.unavailable(error));
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
