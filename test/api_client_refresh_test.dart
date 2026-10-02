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

  group('Fixed server URL (from --dart-define-from-file=.env)', () {
    test('apiBaseUrlProvider reads ApiConfig.defaultBaseUrl verbatim', () {
      final container = ProviderContainer(
        overrides: [
          secureTokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
      );
      addTearDown(container.dispose);

      // Not asserting a literal value: in CI/local `flutter test` (no
      // --dart-define-from-file), ApiConfig.defaultBaseUrl is legitimately ''
      // — see the `main.dart` config-error screen for how that's handled at
      // runtime. This only checks the provider doesn't drift from the config.
      expect(container.read(apiBaseUrlProvider), ApiConfig.defaultBaseUrl);
      expect(
        container.read(apiClientProvider).apiRoot,
        ApiConfig.rootFor(ApiConfig.defaultBaseUrl),
      );
    });

    test('rootFor builds <base>/api/v1 for a configured URL', () {
      expect(
        ApiConfig.rootFor('https://example.ngrok-free.dev'),
        'https://example.ngrok-free.dev/api/v1',
      );
    });

    test('rootFor is empty for an empty base (unconfigured build)', () {
      expect(ApiConfig.rootFor(''), '');
    });
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
