import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/features/notifications/notifications_controller.dart';
import 'package:biometric_mobile/features/notifications/notifications_repository.dart';
import 'package:biometric_mobile/models/app_notification.dart';

import 'helpers.dart';

const _root = 'http://test.local/api/v1';

Map<String, dynamic> _json(int id, {bool read = false}) => {
  'id': id,
  'title': 'Marked Absent',
  'body': 'body',
  'type': 'ABSENCE',
  'is_read': read,
  'sent_at': '2026-09-21T00:01:48+08:00',
  'created_at': '2026-09-21T00:01:47+08:00',
};

FakeResponse _list(Iterable<Map<String, dynamic>> items) => FakeResponse(200, {
  'count': items.length,
  'next': null,
  'previous': null,
  'results': items.toList(),
});

class _Cache implements CacheStore {
  List<AppNotification>? saved;
  @override
  Future<void> saveNotifications(List<AppNotification> notes) async =>
      saved = notes;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test(
    'opening a notification marks it read locally and on the server',
    () async {
      final posted = <String>[];
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter((opts) {
          if (opts.method == 'GET') {
            return _list([_json(7), _json(8, read: true)]);
          }
          posted.add('${opts.method} ${opts.path}');
          return const FakeResponse(200, {'detail': 'read'});
        });
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
        dio: dio,
      );
      final cache = _Cache();
      final container = ProviderContainer(
        overrides: [
          cacheStoreProvider.overrideWithValue(cache),
          notificationsRepositoryProvider.overrideWithValue(
            NotificationsRepository(client),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        notificationsControllerProvider.notifier,
      );
      await controller.load();
      NotificationsState now() =>
          container.read(notificationsControllerProvider);
      expect(now().unreadCount, 1);

      await controller.markRead(7);

      expect(now().items.first.isRead, isTrue);
      expect(now().unreadCount, 0);
      expect(posted, ['POST /notifications/7/read/']);
      expect(cache.saved!.first.isRead, isTrue);

      // Already-read notifications don't hit the server again.
      await controller.markRead(8);
      await controller.markRead(7);
      expect(posted.length, 1);
    },
  );

  test('a failed server call keeps the notification read locally', () async {
    final dio = Dio(BaseOptions(baseUrl: _root))
      ..httpClientAdapter = FakeHttpAdapter(
        (opts) => opts.method == 'GET'
            ? _list([_json(1)])
            : const FakeResponse(404, {'detail': 'Not found.'}),
      );
    final client = ApiClient(
      apiRoot: _root,
      tokenStore: InMemoryTokenStore(),
      onForceLogout: () async {},
      dio: dio,
    );
    final container = ProviderContainer(
      overrides: [
        cacheStoreProvider.overrideWithValue(_Cache()),
        notificationsRepositoryProvider.overrideWithValue(
          NotificationsRepository(client),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(notificationsControllerProvider.notifier);
    await controller.load();

    await controller.markRead(1);
    expect(
      container.read(notificationsControllerProvider).items.single.isRead,
      isTrue,
    );
  });
}
