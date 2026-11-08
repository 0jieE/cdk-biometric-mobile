import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_store.dart';
import '../../models/weekly_hours.dart';
import 'attendance_controller.dart' show attendanceRepositoryProvider;

/// Part-time weekly hours (worked vs. required). Full-timers never load this —
/// [WeeklyController] is only watched from the part-time section of the
/// Attendance screen.
@immutable
class WeeklyState {
  final List<WeeklyHours> weeks;
  final bool loading;
  final bool offline;
  final String? error;
  final DateTime? lastSync;

  const WeeklyState({
    this.weeks = const [],
    this.loading = false,
    this.offline = false,
    this.error,
    this.lastSync,
  });

  bool get isEmpty => weeks.isEmpty;

  /// This week (newest first) — the current, possibly in-progress, week.
  WeeklyHours? get current => weeks.isEmpty ? null : weeks.first;

  /// Every week after the current one, oldest-change-last (as returned).
  List<WeeklyHours> get past => weeks.length <= 1 ? const [] : weeks.sublist(1);

  WeeklyState copyWith({
    List<WeeklyHours>? weeks,
    bool? loading,
    bool? offline,
    String? error,
    bool clearError = false,
    DateTime? lastSync,
  }) {
    return WeeklyState(
      weeks: weeks ?? this.weeks,
      loading: loading ?? this.loading,
      offline: offline ?? this.offline,
      error: clearError ? null : (error ?? this.error),
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

final weeklyControllerProvider =
    NotifierProvider<WeeklyController, WeeklyState>(WeeklyController.new);

class WeeklyController extends Notifier<WeeklyState> {
  CacheStore get _cache => ref.read(cacheStoreProvider);

  @override
  WeeklyState build() => const WeeklyState();

  /// Loads the default window (last 4 weeks ending today — the backend's
  /// default when `start`/`end` are omitted).
  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      state = state.copyWith(loading: true, clearError: true, offline: false);
    }
    try {
      final weeks = await ref.read(attendanceRepositoryProvider).fetchWeekly();
      await _cache.saveWeekly(weeks);
      state = state.copyWith(
        weeks: weeks,
        loading: false,
        offline: false,
        clearError: true,
        lastSync: await _cache.lastSyncWeekly(),
      );
    } on NetworkUnavailable {
      if (!await _loadFromCache()) {
        state = state.copyWith(
          loading: false,
          error: 'You are offline. Weekly hours will appear once you reconnect.',
        );
      }
    } on ApiException catch (e) {
      if (!await _loadFromCache()) {
        state = state.copyWith(loading: false, error: e.message);
      }
    } catch (e) {
      debugPrint('weekly hours load failed: $e');
      if (!await _loadFromCache()) {
        state = state.copyWith(
          loading: false,
          error: 'Could not load weekly hours.',
        );
      }
    }
  }

  Future<bool> _loadFromCache() async {
    final cached = await _cache.readWeekly();
    if (cached == null) return false;
    final lastSync = await _cache.lastSyncWeekly();
    state = state.copyWith(
      weeks: cached,
      loading: false,
      offline: true,
      clearError: true,
      lastSync: lastSync,
    );
    return true;
  }

  Future<void> refresh() => load(showSpinner: false);
}
