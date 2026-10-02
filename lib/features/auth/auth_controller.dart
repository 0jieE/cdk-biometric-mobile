import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_store.dart';
import '../../core/storage/secure_token_store.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStore: ref.watch(secureTokenStoreProvider),
  );
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.unknown();

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStore get _tokens => ref.read(secureTokenStoreProvider);
  CacheStore get _cache => ref.read(cacheStoreProvider);

  /// Called once at startup. If a refresh token exists we treat the session as
  /// authenticated and (best-effort) refresh the cached profile; the dio
  /// interceptor will refresh the access token on the first real call and
  /// force logout if the refresh token is dead.
  Future<void> bootstrap() async {
    state = state.copyWith(busy: true);
    final hasSession = await _repo.hasSession();
    if (!hasSession) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    // Show cached profile immediately if we have one.
    final cached = _cache.readProfile();
    state = AuthState(status: AuthStatus.authenticated, employee: cached);

    // Best-effort refresh of the profile; keep the session even if offline.
    try {
      final profile = await _repo.fetchProfile();
      await _cache.saveProfile(profile);
      state = state.copyWith(employee: profile);
    } on NetworkUnavailable {
      // Offline — keep cached profile and stay logged in.
    } catch (e) {
      // Any other error (e.g. 401 that couldn't be refreshed) already routes
      // through forceLogout via the interceptor.
      debugPrint('bootstrap profile refresh failed: $e');
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.login(username: username, password: password);
      final profile = await _repo.fetchProfile();
      await _cache.saveProfile(profile);
      state = AuthState(status: AuthStatus.authenticated, employee: profile);
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    } on NetworkUnavailable {
      state = state.copyWith(
        busy: false,
        error:
            'Cannot reach the server. Check your internet connection and '
            'try again.',
      );
    } catch (e) {
      state = state.copyWith(busy: false, error: 'Login failed: $e');
    }
  }

  /// Uploads a new profile photo and updates the profile (and its offline
  /// copy) with the returned URL. Throws [ApiException]/[NetworkUnavailable].
  Future<void> updatePhoto(String filePath) async {
    final url = await _repo.uploadPhoto(filePath);
    final current = state.employee;
    if (current == null) return;
    final updated = current.copyWith(photoUrl: url);
    await _cache.saveProfile(updated);
    state = state.copyWith(employee: updated);
  }

  /// Changes the username and updates the profile (and its offline copy).
  /// See [AuthRepository.changeUsername] for the errors it can throw.
  Future<void> changeUsername({
    required String username,
    required String currentPassword,
  }) async {
    final stored = await _repo.changeUsername(
      username: username,
      currentPassword: currentPassword,
    );
    final current = state.employee;
    if (current == null) return;
    final updated = current.copyWith(username: stored);
    await _cache.saveProfile(updated);
    state = state.copyWith(employee: updated);
  }

  /// Changes the password and stores the new tokens; see
  /// [AuthRepository.changePassword] for the errors it can throw.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) =>
      _repo.changePassword(oldPassword: oldPassword, newPassword: newPassword);

  /// User-initiated logout: clear tokens + cache and return to login.
  Future<void> logout() async {
    await _tokens.clear();
    await _cache.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Called by the auth interceptor when the refresh token is no longer valid.
  Future<void> forceLogout({String? message}) async {
    await _tokens.clear();
    await _cache.clear();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      busy: false,
      clearEmployee: true,
      error: message ?? 'Your session expired. Please log in again.',
    );
  }
}
