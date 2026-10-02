import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/config/api_config.dart';
import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/time.dart';

import 'helpers.dart';

const _root = 'http://test.local/api/v1';

void main() {
  group('ApiClient', () {
    test('sends the ngrok skip-warning header by default', () {
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
      );
      expect(client.dio.options.headers['ngrok-skip-browser-warning'], 'true');
    });

    test(
      'a 4xx surfaces as ApiException via mapDioError (403 is explained)',
      () async {
        final dio = Dio(BaseOptions(baseUrl: _root))
          ..httpClientAdapter = FakeHttpAdapter(
            (_) => const FakeResponse(403, {'detail': 'nope'}),
          );
        final client = ApiClient(
          apiRoot: _root,
          tokenStore: InMemoryTokenStore(),
          onForceLogout: () async {},
          dio: dio,
        );
        try {
          await client.dio.get(ApiConfig.me);
          fail('expected DioException');
        } on DioException catch (e) {
          final mapped = mapDioError(e) as ApiException;
          expect(mapped.statusCode, 403);
        }
      },
    );
  });

  test('the API client always points at the fixed public server URL', () {
    final container = ProviderContainer(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(apiBaseUrlProvider), ApiConfig.defaultBaseUrl);
    expect(ApiConfig.defaultBaseUrl, startsWith('https://'));
    expect(
      container.read(apiClientProvider).apiRoot,
      '${ApiConfig.defaultBaseUrl}/api/v1',
    );
  });

  group('Manila time', () {
    test(
      'UTC attendance time and +08:00 notification time are the same moment',
      () {
        final a = parseApiInstant('2026-09-14T12:22:08Z')!;
        final b = parseApiInstant('2026-09-14T20:22:08+08:00')!;
        expect(a, b);
        final m = toManila(a);
        expect(m.hour, 20);
        expect(m.minute, 22);
        expect(m.day, 14);
      },
    );

    test('12:22Z is 8:22 PM Manila, and late-UTC rolls to the next day', () {
      expect(toManila(parseApiInstant('2026-09-14T12:22:00Z')!).hour, 20);
      final next = toManila(parseApiInstant('2026-09-14T17:00:00Z')!);
      expect((next.day, next.hour), (15, 1));
    });
  });
}
