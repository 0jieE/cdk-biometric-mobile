import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/api_config.dart';
import 'network/api_client.dart';
import 'storage/cache_store.dart';
import 'storage/secure_token_store.dart';
import 'storage/settings_store.dart';
import '../features/auth/auth_controller.dart';

/// Secure JWT token store.
final secureTokenStoreProvider = Provider<TokenStore>((ref) {
  return SecureTokenStore();
});

/// Offline cache. Overridden in [main] with an already-opened Hive box.
final cacheStoreProvider = Provider<CacheStore>((ref) {
  throw UnimplementedError(
    'cacheStoreProvider must be overridden with an opened CacheStore',
  );
});

/// App settings (theme). Overridden in [main] with an opened Hive box.
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  throw UnimplementedError(
    'settingsStoreProvider must be overridden with an opened SettingsStore',
  );
});

/// The API base URL (fixed; see [ApiConfig.defaultBaseUrl]). A provider so
/// tests can override it.
final apiBaseUrlProvider = Provider<String>((ref) => ApiConfig.defaultBaseUrl);

/// Configured Dio-backed API client. Its auth interceptor calls [AuthController.forceLogout] when the
/// session cannot be refreshed.
final apiClientProvider = Provider<ApiClient>((ref) {
  final base = ref.watch(apiBaseUrlProvider);
  final tokenStore = ref.watch(secureTokenStoreProvider);
  return ApiClient(
    apiRoot: ApiConfig.rootFor(base),
    tokenStore: tokenStore,
    onForceLogout: () async {
      await ref.read(authControllerProvider.notifier).forceLogout();
    },
    onPasswordChanged: () async {
      await ref
          .read(authControllerProvider.notifier)
          .forceLogout(
            message:
                'Your password was changed on another device. '
                'Please log in again.',
          );
    },
  );
});
