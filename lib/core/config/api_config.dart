/// Central API configuration.
///
/// The server URL is fixed at build time ([ApiConfig.defaultBaseUrl]); there is
/// no in-app server setting. It is NOT hardcoded here — it comes from a local,
/// gitignored `.env` file (copy `.env.example` to `.env` and fill it in), passed
/// to Flutter with `--dart-define-from-file=.env`. See the README.
class ApiConfig {
  ApiConfig._();

  /// Public backend URL (ngrok free tier). Read from `API_BASE_URL` in `.env`
  /// at build time; empty if `.env` wasn't passed, which [AppConfigGuard] (see
  /// `main.dart`) turns into a clear startup error instead of a silently broken
  /// app.
  static const String defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

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
