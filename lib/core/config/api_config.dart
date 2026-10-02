/// Central API configuration.
///
/// The server URL is fixed at build time ([ApiConfig.defaultBaseUrl]); there is
/// no in-app server setting. If the public URL changes, update it here or build
/// with `--dart-define=API_BASE_URL=...`.
class ApiConfig {
  ApiConfig._();

  /// Public backend URL (ngrok free tier). Override at build time with
  /// `--dart-define=API_BASE_URL=...`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sympathy-uniformly-rival.ngrok-free.dev',
  );

  /// Headers for image downloads (no JSON content type on a GET).
  static const Map<String, String> imageHeaders = {
    'ngrok-skip-browser-warning': 'true',
  };

  /// ngrok's free tier can serve an HTML browser-warning page instead of the
  /// API response; this header makes it skip that page. Harmless elsewhere.
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  /// All endpoints live under `/api/v1/`.
  static const String apiPrefix = '/api/v1';

  /// Build the API root (`<base>/api/v1`) for a given server base URL.
  /// Returns '' when [base] is empty.
  static String rootFor(String base) => base.isEmpty ? '' : '$base$apiPrefix';

  // Endpoint paths (relative to the API root).
  static const String health = '/health/';
  static const String login = '/auth/login/';
  static const String refresh = '/auth/refresh/';
  static const String me = '/me/';
  static const String mePhoto = '/me/photo/';
  static const String mePassword = '/me/password/';
  static const String meUsername = '/me/username/';
  static const String attendance = '/attendance/';
  static const String attendanceSummary = '/attendance/summary/';
  static const String notifications = '/notifications/';
  static const String deviceRegister = '/devices/register/';

  /// `POST` marks one notification as read.
  static String notificationRead(int id) => '/notifications/$id/read/';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
