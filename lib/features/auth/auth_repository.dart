import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_token_store.dart';
import '../../models/employee.dart';

/// Talks to the auth + profile endpoints and manages token persistence.
class AuthRepository {
  AuthRepository({required ApiClient apiClient, required TokenStore tokenStore})
    : _dio = apiClient.dio,
      _tokenStore = tokenStore;

  final Dio _dio;
  final TokenStore _tokenStore;

  /// Logs in with username (lowercased employee_no) + password.
  /// On success, persists access + refresh tokens. Throws [ApiException] on
  /// bad credentials or [NetworkUnavailable] when the backend is unreachable.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.login,
        data: {'username': username.trim(), 'password': password},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final access = res.data['access'] as String?;
        final refresh = res.data['refresh'] as String?;
        if (access != null && refresh != null) {
          await _tokenStore.saveTokens(access: access, refresh: refresh);
          return;
        }
      }
      throw ApiException(res.statusCode, 'Login failed. Please try again.');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const ApiException(401, 'Invalid employee number or password.');
      }
      throw mapDioError(e);
    }
  }

  /// Fetches and returns the employee profile from `/me/`.
  Future<Employee> fetchProfile() async {
    try {
      final res = await _dio.get(ApiConfig.me);
      if (res.statusCode == 200 && res.data is Map) {
        return Employee.fromJson(Map<String, dynamic>.from(res.data as Map));
      }
      throw ApiException(res.statusCode, 'Could not load profile.');
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Uploads [filePath] as the profile photo (multipart field `photo`; JPEG,
  /// PNG or WebP up to 10 MB). Returns the new absolute `photo_url`.
  Future<String> uploadPhoto(String filePath) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split(RegExp(r'[\\/]')).last,
        ),
      });
      final res = await _dio.post(ApiConfig.mePhoto, data: form);
      final url = res.data is Map ? res.data['photo_url'] as String? : null;
      if (url == null || url.isEmpty) {
        throw ApiException(res.statusCode, 'Could not update the photo.');
      }
      return url;
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Changes the login username (needs the current password). Returns the
  /// normalised username the server stored. Nobody is signed out; the tokens
  /// keep working. 400 carries `fieldErrors` for `username` /
  /// `current_password`; the endpoint shares the password endpoint's 429
  /// throttle.
  Future<String> changeUsername({
    required String username,
    required String currentPassword,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.meUsername,
        data: {'username': username, 'current_password': currentPassword},
      );
      final stored = res.data is Map ? res.data['username'] as String? : null;
      if (stored == null || stored.isEmpty) {
        throw ApiException(res.statusCode, 'Could not change the username.');
      }
      return stored;
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Changes the password. Every older token stops working, so the response's
  /// fresh access/refresh pair replaces the stored tokens for this device.
  /// Throws [ApiException] (with `fieldErrors` for `old_password` /
  /// `new_password` on a 400, or a 429 when throttled).
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.mePassword,
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
      final data = res.data;
      final access = data is Map ? data['access'] as String? : null;
      final refresh = data is Map ? data['refresh'] as String? : null;
      if (access == null || refresh == null) {
        throw ApiException(res.statusCode, 'Could not change the password.');
      }
      await _tokenStore.saveTokens(access: access, refresh: refresh);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  Future<bool> hasSession() => _tokenStore.hasTokens();

  Future<void> clearTokens() => _tokenStore.clear();
}
