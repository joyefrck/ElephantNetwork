import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

abstract interface class LegacyTokenStore {
  Future<String?> readToken();

  Future<void> deleteToken();
}

class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              sharedPreferencesName: 'elephant_network_secure_storage',
              preferencesKeyPrefix: 'elephant_network',
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}

class SharedPreferencesLegacyTokenStore implements LegacyTokenStore {
  const SharedPreferencesLegacyTokenStore();

  static const _tokenKey = 'auth_token';

  @override
  Future<void> deleteToken() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
  }

  @override
  Future<String?> readToken() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_tokenKey);
  }
}

class XboardSessionStore {
  XboardSessionStore({
    SecureKeyValueStore? secureStore,
    LegacyTokenStore? legacyStore,
  }) : _secureStore = secureStore ?? PlatformSecureKeyValueStore(),
       _legacyStore = legacyStore ?? const SharedPreferencesLegacyTokenStore();

  static const _tokenKey = 'xboard.auth_token.v2';

  final SecureKeyValueStore _secureStore;
  final LegacyTokenStore _legacyStore;

  Future<String?> readToken() async {
    final secureToken = await _secureStore.read(_tokenKey);
    if (secureToken != null && secureToken.trim().isNotEmpty) {
      return secureToken;
    }
    final legacyToken = await _legacyStore.readToken();
    if (legacyToken == null || legacyToken.trim().isEmpty) {
      return null;
    }
    await _secureStore.write(_tokenKey, legacyToken);
    await _legacyStore.deleteToken();
    return legacyToken;
  }

  Future<void> saveToken(String token) async {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token');
    }
    await _secureStore.write(_tokenKey, token);
    await _legacyStore.deleteToken();
  }

  Future<void> clear() async {
    await _secureStore.delete(_tokenKey);
    await _legacyStore.deleteToken();
  }
}
