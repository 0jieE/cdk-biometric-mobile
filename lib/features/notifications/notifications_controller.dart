import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_store.dart';
import '../../models/app_notification.dart';
import 'notifications_repository.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(ref.watch(apiClientProvider));
});

@immutable
class NotificationsState {
  final List<AppNotification> items;
  final bool loading;
  final bool offline;
  final String? error;
  final DateTime? lastSync;

  const NotificationsState({
    this.items = const [],
    this.loading = false,
    this.offline = false,
    this.error,
    this.lastSync,
  });

  bool get isEmpty => items.isEmpty;
  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationsState copyWith({
    List<AppNotification>? items,
    bool? loading,
    bool? offline,
    String? error,
    bool clearError = false,
    DateTime? lastSync,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      offline: offline ?? this.offline,
      error: clearError ? null : (error ?? this.error),
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
      NotificationsController.new,
    );

class NotificationsController extends Notifier<NotificationsState> {
  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);
  CacheStore get _cache => ref.read(cacheStoreProvider);

  @override
  NotificationsState build() => const NotificationsState();

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      state = state.copyWith(loading: true, clearError: true, offline: false);
    }
    try {
      final items = await _repo.fetch();
      await _cache.saveNotifications(items);
      state = state.copyWith(
        items: items,
        loading: false,
        offline: false,
        clearError: true,
        lastSync: _cache.lastSyncNotifications(),
      );
    } on NetworkUnavailable {
      if (!_loadFromCache()) {
        state = state.copyWith(
          loading: false,
          error:
              'You are offline. Notifications will appear once you '
              'reconnect.',
        );
      }
    } on ApiException catch (e) {
      if (!_loadFromCache()) {
        state = state.copyWith(loading: false, error: e.message);
      }
    } catch (e) {
      debugPrint('notifications load failed: $e');
      if (!_loadFromCache()) {
        state = state.copyWith(
          loading: false,
          error: 'Could not load notifications.',
        );
      }
    }
  }

  bool _loadFromCache() {
    final cached = _cache.readNotifications();
    if (cached == null) return false;
    state = state.copyWith(
      items: cached,
      loading: false,
      offline: true,
      clearError: true,
      lastSync: _cache.lastSyncNotifications(),
    );
    return true;
  }

  Future<void> refresh() => load(showSpinner: false);

  /// Mark [id] as read when the user opens it. Updates the UI (and the offline
  /// cache) immediately, then tells the backend; if that call fails the notice
  /// stays read locally and the next successful refresh reflects the server.
  Future<void> markRead(int id) async {
    final index = state.items.indexWhere((n) => n.id == id);
    if (index < 0 || state.items[index].isRead) return;

    final items = [...state.items];
    items[index] = items[index].copyWith(isRead: true);
    state = state.copyWith(items: items);
    await _cache.saveNotifications(items);

    try {
      await _repo.markRead(id);
    } catch (e) {
      debugPrint('mark notification $id read failed: $e');
    }
  }
}
