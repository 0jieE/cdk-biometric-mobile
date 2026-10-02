import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over JWT token persistence so it can be faked in tests.
abstract class TokenStore {
  Future<void> saveTokens({required String access, required String refresh});
  Future<void> saveAccess(String access);
  Future<String?> readAccess();
  Future<String?> readRefresh();
  Future<bool> hasTokens();
  Future<void> clear();
}

/// Stores the JWT access + refresh tokens in the platform secure store
/// (Keystore on Android, Keychain on iOS).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'jwt_access';
  static const _kRefresh = 'jwt_refresh';

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  @override
  Future<void> saveAccess(String access) =>
      _storage.write(key: _kAccess, value: access);

  @override
  Future<String?> readAccess() => _storage.read(key: _kAccess);

  @override
  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  @override
  Future<bool> hasTokens() async {
    final refresh = await readRefresh();
    return refresh != null && refresh.isNotEmpty;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
