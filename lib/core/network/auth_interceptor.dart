import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../storage/secure_token_store.dart';

/// Dio interceptor that:
///  1. Attaches the current access token to every request.
///  2. On a 401, transparently refreshes the access token using the refresh
///     token and retries the original request exactly once.
///  3. If refresh fails (expired/invalid refresh token), clears tokens and
///     invokes [onForceLogout] so the app can route back to login.
///
/// A separate Dio instance ([_refreshDio]) performs the refresh call so it does
/// not recurse through this interceptor.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.onForceLogout,
    this.onPasswordChanged,
    required TokenStore tokenStore,
    String apiRoot = '',
    Dio? refreshDio,
  }) : _tokenStore = tokenStore,
       _refreshDio =
           refreshDio ??
           Dio(
             BaseOptions(
               baseUrl: apiRoot,
               connectTimeout: ApiConfig.connectTimeout,
               receiveTimeout: ApiConfig.receiveTimeout,
               headers: ApiConfig.defaultHeaders,
             ),
           );

  final TokenStore _tokenStore;
  final Dio _refreshDio;

  /// Called when the session can no longer be recovered.
  final Future<void> Function() onForceLogout;

  /// Called instead of [onForceLogout] when the refresh was rejected with
  /// `code: password_changed` (password changed on another device / by an
  /// admin), so the app can say why. Falls back to [onForceLogout] when null.
  final Future<void> Function()? onPasswordChanged;

  /// Header flag marking a request that has already been retried after refresh,
  /// so we never loop.
  static const _retriedFlag = 'x-retried-after-refresh';

  /// Endpoints that must never trigger a refresh attempt.
  bool _isAuthEndpoint(String path) =>
      path.contains(ApiConfig.login) || path.contains(ApiConfig.refresh);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAuthEndpoint(options.path)) {
      final access = await _tokenStore.readAccess();
      if (access != null && access.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final request = err.requestOptions;

    final shouldTryRefresh =
        response?.statusCode == 401 &&
        !_isAuthEndpoint(request.path) &&
        request.headers[_retriedFlag] != true;

    if (!shouldTryRefresh) {
      return handler.next(err);
    }

    final refreshed = await _refreshAccessToken();
    final newAccess = refreshed.access;
    if (newAccess == null) {
      // Refresh failed → session is dead.
      await _tokenStore.clear();
      if (refreshed.passwordChanged && onPasswordChanged != null) {
        await onPasswordChanged!();
      } else {
        await onForceLogout();
      }
      return handler.next(err);
    }

    // Retry the original request once with the new token.
    try {
      request.headers['Authorization'] = 'Bearer $newAccess';
      request.headers[_retriedFlag] = true;
      final retryResponse = await _refreshDio.fetch(request);
      return handler.resolve(retryResponse);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }

  /// Returns a fresh access token (null if refresh is not possible), and
  /// whether the server said the password was changed.
  Future<({String? access, bool passwordChanged})> _refreshAccessToken() async {
    final refresh = await _tokenStore.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      return (access: null, passwordChanged: false);
    }
    try {
      final res = await _refreshDio.post(
        ApiConfig.refresh,
        data: {'refresh': refresh},
      );
      final access = res.data['access'] as String?;
      if (access == null || access.isEmpty) {
        return (access: null, passwordChanged: false);
      }
      await _tokenStore.saveAccess(access);
      return (access: access, passwordChanged: false);
    } on DioException catch (e) {
      final data = e.response?.data;
      final changed =
          e.response?.statusCode == 401 &&
          data is Map &&
          data['code'] == 'password_changed';
      return (access: null, passwordChanged: changed);
    }
  }
}
