import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/config/api_config.dart';
import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/network/auth_interceptor.dart';
import 'package:biometric_mobile/features/auth/auth_repository.dart';

import 'helpers.dart';

/// Fixed API root for the fake adapter (`<base>/api/v1`).
const testRoot = 'http://test.local/api/v1';

void main() {
  group('Auth', () {
    test('successful login stores access + refresh tokens', () async {
      final tokenStore = InMemoryTokenStore();
      final dio = Dio(BaseOptions(baseUrl: testRoot))
        ..httpClientAdapter = FakeHttpAdapter((opts) {
          if (opts.path == ApiConfig.login) {
            return const FakeResponse(200, {
              'access': 'ACCESS-TOKEN',
              'refresh': 'REFRESH-TOKEN',
            });
          }
          return const FakeResponse(404, {'detail': 'not found'});
        });
      final client = ApiClient(
        apiRoot: testRoot,
        tokenStore: tokenStore,
        onForceLogout: () async {},
        dio: dio,
      );
      final repo = AuthRepository(apiClient: client, tokenStore: tokenStore);

      await repo.login(username: 'emp-1001', password: 'employee12345');

      expect(tokenStore.access, 'ACCESS-TOKEN');
      expect(tokenStore.refresh, 'REFRESH-TOKEN');
      expect(await tokenStore.hasTokens(), isTrue);
    });

    test(
      'bad credentials throw ApiException and do not store tokens',
      () async {
        final tokenStore = InMemoryTokenStore();
        final dio = Dio(BaseOptions(baseUrl: testRoot))
          ..httpClientAdapter = FakeHttpAdapter(
            (_) => const FakeResponse(401, {'detail': 'No active account'}),
          );
        final client = ApiClient(
          apiRoot: testRoot,
          tokenStore: tokenStore,
          onForceLogout: () async {},
          dio: dio,
        );
        final repo = AuthRepository(apiClient: client, tokenStore: tokenStore);

        await expectLater(
          repo.login(username: 'emp-1001', password: 'wrong'),
          throwsA(isA<ApiException>()),
        );
        expect(await tokenStore.hasTokens(), isFalse);
      },
    );

    test('a failed token refresh forces logout and clears tokens', () async {
      final tokenStore = InMemoryTokenStore()
        ..access = 'expired'
        ..refresh = 'dead-refresh';
      var forcedOut = false;

      // The refresh endpoint rejects the refresh token (401).
      final refreshDio = Dio(BaseOptions(baseUrl: testRoot))
        ..httpClientAdapter = FakeHttpAdapter(
          (_) => const FakeResponse(401, {'detail': 'token not valid'}),
        );

      final interceptor = AuthInterceptor(
        tokenStore: tokenStore,
        onForceLogout: () async => forcedOut = true,
        refreshDio: refreshDio,
      );

      // A protected call that always returns 401 → triggers the refresh path.
      final dio = Dio(BaseOptions(baseUrl: testRoot))
        ..httpClientAdapter = FakeHttpAdapter(
          (_) => const FakeResponse(401, {'detail': 'unauthorized'}),
        )
        ..interceptors.add(interceptor);

      await expectLater(dio.get(ApiConfig.me), throwsA(isA<DioException>()));

      expect(forcedOut, isTrue, reason: 'onForceLogout should fire');
      expect(await tokenStore.readRefresh(), isNull);
      expect(await tokenStore.readAccess(), isNull);
    });
  });
}
