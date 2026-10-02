import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../storage/secure_token_store.dart';
import 'auth_interceptor.dart';

/// Thin wrapper around a configured [Dio] instance pointed at the DRF API.
///
/// [apiRoot] is the fixed `<base>/api/v1` (see [ApiConfig.defaultBaseUrl]).
class ApiClient {
  ApiClient({
    required this.apiRoot,
    required TokenStore tokenStore,
    required Future<void> Function() onForceLogout,
    Future<void> Function()? onPasswordChanged,
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: apiRoot,
               connectTimeout: ApiConfig.connectTimeout,
               receiveTimeout: ApiConfig.receiveTimeout,
               // Non-2xx responses throw DioException so the auth interceptor
               // sees 401s; repositories translate them via [mapDioError].
               headers: ApiConfig.defaultHeaders,
             ),
           ) {
    this.dio.interceptors.add(
      AuthInterceptor(
        apiRoot: apiRoot,
        tokenStore: tokenStore,
        onForceLogout: onForceLogout,
        onPasswordChanged: onPasswordChanged,
      ),
    );
  }

  final String apiRoot;
  final Dio dio;
}

/// Raised when the backend is unreachable (no network / connection refused /
/// timeout). Callers use this to decide whether to fall back to cache.
class NetworkUnavailable implements Exception {
  final String message;
  const NetworkUnavailable([this.message = 'Backend unreachable']);
  @override
  String toString() => 'NetworkUnavailable: $message';
}

/// Raised for a 4xx the caller should surface (e.g. bad credentials).
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  /// Per-field validation messages from a 400, e.g.
  /// `{"new_password": "This password is too common."}`.
  final Map<String, String> fieldErrors;

  const ApiException(
    this.statusCode,
    this.message, {
    this.fieldErrors = const {},
  });
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Translate a [DioException] into one of our typed exceptions.
Object mapDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return const NetworkUnavailable();
    case DioExceptionType.badResponse:
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] != null)
          ? '${data['detail']}'
          : null;
      // DRF validation errors: {"field": ["message", ...]}.
      final fields = <String, String>{};
      if (data is Map) {
        data.forEach((key, value) {
          if (key == 'detail' || key == 'code' || key == 'messages') return;
          if (value is List && value.isNotEmpty) {
            fields['$key'] = value.map((m) => '$m').join('\n');
          } else if (value is String) {
            fields['$key'] = value;
          }
        });
      }
      return ApiException(status, switch (status) {
        403 => 'This account cannot use the employee app.',
        429 => 'Too many attempts. Please wait a minute and try again.',
        _ =>
          detail ??
              (fields.values.isNotEmpty
                  ? fields.values.first
                  : 'Request failed ($status).'),
      }, fieldErrors: fields);
    default:
      // unknown / cancel / badCertificate → treat as network problem.
      return const NetworkUnavailable();
  }
}
