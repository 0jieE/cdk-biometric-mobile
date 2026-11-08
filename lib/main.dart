import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/api_config.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'core/storage/app_database.dart';
import 'core/storage/cache_store.dart';
import 'core/storage/settings_store.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/notifications/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The server URL comes from `.env` (--dart-define-from-file), not from
  // source — see api_config.dart. Fail loudly and clearly instead of running
  // with an empty base URL that would make every request fail silently.
  if (ApiConfig.defaultBaseUrl.isEmpty) {
    runApp(const _ConfigErrorApp());
    return;
  }

  // Local SQLite database: the offline cache + app settings. Settings live in
  // their own table so they survive logout (which clears only the cache).
  final db = await AppDatabase.open();
  final cacheStore = CacheStore(db);
  final settingsStore = await SqliteSettingsStore.open(db);

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

/// Shown instead of the real app when `API_BASE_URL` wasn't supplied at build
/// time, so a missing `.env` reads as a clear setup error, not a frozen splash
/// screen or endless connection failures.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(AppAccent.purple, Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Missing build configuration',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'API_BASE_URL was not set. Copy .env.example to .env, '
                    'fill in the values, and run with '
                    '--dart-define-from-file=.env (see the README).',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
