import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart';
import 'core/storage/cache_store.dart';
import 'core/storage/settings_store.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/notifications/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline cache + app settings (Hive). Settings live in their own box so the
  // saved server URL survives logout (which clears only the cache box).
  await Hive.initFlutter();
  final cacheStore = await CacheStore.open();
  final settingsStore = await HiveSettingsStore.open();

  // Firebase / FCM is optional. If google-services.json is missing (or any
  // init error occurs) the app still runs and simply skips push registration.
  final firebaseReady = await _initFirebase();

  final container = ProviderContainer(
    overrides: [
      cacheStoreProvider.overrideWithValue(cacheStore),
      settingsStoreProvider.overrideWithValue(settingsStore),
      firebaseReadyProvider.overrideWithValue(firebaseReady),
    ],
  );

  // Set up messaging listeners (no-op when Firebase isn't configured).
  await container.read(fcmServiceProvider).initialize();

  // Decide login vs home before the first frame settles.
  container.read(authControllerProvider.notifier).bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BiometricApp(),
    ),
  );
}

Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    return true;
  } catch (e) {
    // Keep running without push if Firebase is unreachable/misconfigured.
    debugPrint('Firebase init failed — running without push. ($e)');
    return false;
  }
}

class BiometricApp extends ConsumerWidget {
  const BiometricApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeSettings = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'CDK Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(themeSettings.accent, Brightness.light),
      darkTheme: AppTheme.themeFor(themeSettings.accent, Brightness.dark),
      themeMode: themeSettings.mode,
      routerConfig: router,
    );
  }
}
