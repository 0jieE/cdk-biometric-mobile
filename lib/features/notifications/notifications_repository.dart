import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../models/app_notification.dart';

/// Fetches the employee's notifications and registers this device's FCM token.
class NotificationsRepository {
  NotificationsRepository(ApiClient client) : _dio = client.dio;

  final Dio _dio;

  /// First page of notifications (page size 25, newest first per backend).
  Future<List<AppNotification>> fetch() async {
    try {
      final res = await _dio.get(ApiConfig.notifications);
      if (res.statusCode == 200 && res.data is Map) {
        final results = (res.data['results'] as List? ?? const []);
        return results
            .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      throw ApiException(res.statusCode, 'Could not load notifications.');
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Tell the backend this notification has been opened.
  Future<void> markRead(int id) async {
    try {
      await _dio.post(ApiConfig.notificationRead(id));
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Register (or update) this phone's FCM token with the backend.
  /// [platform] must be ANDROID or IOS.
  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.post(
        ApiConfig.deviceRegister,
        data: {'fcm_token': fcmToken, 'platform': platform},
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
