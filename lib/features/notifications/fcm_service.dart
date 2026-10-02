import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/router/app_router.dart';
import '../../firebase_options.dart';
import 'notifications_controller.dart';

/// Whether `Firebase.initializeApp()` succeeded at startup. Overridden in
/// [main]. When false, every FCM operation is a no-op so the app runs fine
/// without `google-services.json`.
final firebaseReadyProvider = Provider<bool>((ref) => false);

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref);
});

/// Background/terminated message handler. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is available in this isolate. Safe to call repeatedly.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Not configured — nothing to do.
  }
  // The OS displays the notification tray entry itself for background messages;
  // no extra work needed here.
}

/// Wraps firebase_messaging + flutter_local_notifications. All methods are
/// safe to call when Firebase is not configured (they early-return).
class FcmService {
  FcmService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'attendance_alerts',
    'Attendance alerts',
    description: 'Late/absent notifications from the attendance system',
    importance: Importance.high,
  );

  bool get _ready => _ref.read(firebaseReadyProvider);

  /// Set up local-notification plumbing and message listeners. Call once at
  /// startup (after Firebase init attempt).
  Future<void> initialize() async {
    if (!_ready) {
      debugPrint('FCM: Firebase not configured — skipping messaging setup.');
      return;
    }

    // Local notifications (used to display foreground pushes).
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (_) => _goToNotificationsTab(),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    // Permissions (Android 13+ / iOS).
    await FirebaseMessaging.instance.requestPermission();

    // Foreground messages → show a local notification.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tapped from background → jump to the Notifications tab.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _goToNotificationsTab());

    // Cold start from a notification tap.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _goToNotificationsTab();

    // Re-register whenever the token rotates.
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
  }

  /// Called after a successful login to register this device's push token.
  Future<void> syncTokenAfterLogin() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugPrint('FCM: could not fetch/register token: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
    try {
      await _ref
          .read(notificationsRepositoryProvider)
          .registerDevice(fcmToken: token, platform: platform);
      debugPrint('FCM: device registered ($platform).');
    } on NetworkUnavailable {
      debugPrint('FCM: offline — will re-register on next token refresh.');
    } catch (e) {
      debugPrint('FCM: device registration failed: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? 'Attendance';
    final body = n?.body ?? message.data['body']?.toString() ?? '';
    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
    // Refresh the in-app list so the new notification appears.
    _ref.read(notificationsControllerProvider.notifier).refresh();
  }

  void _goToNotificationsTab() {
    // Notifications tab index is 1 (Attendance=0, Notifications=1, Profile=2).
    _ref.read(selectedTabProvider.notifier).set(1);
    _ref.read(notificationsControllerProvider.notifier).refresh();
  }
}
