import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_store.dart';
import '../../core/time.dart';
import '../../models/attendance_day.dart';
import '../../models/monthly_summary.dart';
import 'attendance_repository.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(apiClientProvider));
});

/// Cache key for a date range: `YYYY-MM-DD..YYYY-MM-DD`.
String rangeKey(DateTimeRange r) =>
    '${formatApiDate(r.start)}..${formatApiDate(r.end)}';

/// Default filter: the 1st of the current month (Asia/Manila) up to today.
DateTimeRange defaultRange() {
  final today = toManila(DateTime.now());
  final day = DateTime(today.year, today.month, today.day);
  return DateTimeRange(start: DateTime(day.year, day.month, 1), end: day);
}

@immutable
class AttendanceState {
  final DateTimeRange range; // date range currently shown
  final List<AttendanceDay> days;
  final MonthlySummary summary;
  final bool loading;

  /// True when the displayed data came from the offline cache after a network
  /// failure (drives the "Offline — showing saved data" banner).
  final bool offline;

  /// True when there is genuinely no data to show and no cache to fall back on.
  final String? error;
  final DateTime? lastSync;

  const AttendanceState({
    required this.range,
    this.days = const [],
    this.summary = MonthlySummary.empty,
    this.loading = false,
    this.offline = false,
    this.error,
    this.lastSync,
  });

  bool get isEmpty => days.isEmpty;

  AttendanceState copyWith({
    DateTimeRange? range,
    List<AttendanceDay>? days,
    MonthlySummary? summary,
    bool? loading,
    bool? offline,
    String? error,
    bool clearError = false,
    DateTime? lastSync,
  }) {
    return AttendanceState(
      range: range ?? this.range,
      days: days ?? this.days,
      summary: summary ?? this.summary,
      loading: loading ?? this.loading,
      offline: offline ?? this.offline,
      error: clearError ? null : (error ?? this.error),
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

final attendanceControllerProvider =
    NotifierProvider<AttendanceController, AttendanceState>(
      AttendanceController.new,
    );

class AttendanceController extends Notifier<AttendanceState> {
  AttendanceRepository get _repo => ref.read(attendanceRepositoryProvider);
  CacheStore get _cache => ref.read(cacheStoreProvider);

  @override
  AttendanceState build() => AttendanceState(range: defaultRange());

  /// Switch to a different date range and load it. Clears the old rows first so
  /// the summary never shows numbers from a previous range.
  Future<void> selectRange(DateTimeRange range) async {
    state = state.copyWith(
      range: range,
      days: const [],
      summary: MonthlySummary.empty,
      clearError: true,
    );
    await load();
  }

  /// Load the currently-selected range. Tries the network first; on a network
  /// failure it falls back to the Hive cache and flags [offline]. The summary
  /// is derived from the loaded days.
  Future<void> load({bool showSpinner = true}) async {
    final range = state.range;
    final key = rangeKey(range);
    // A newer selectRange() supersedes this call; ignore its late result.
    bool stale() => state.range != range;

    if (showSpinner) {
      state = state.copyWith(loading: true, clearError: true, offline: false);
    }

    try {
      final days = await _repo.fetchRange(range.start, range.end);
      if (stale()) return;

      // Cache on every successful fetch (offline synchronization).
      await _cache.saveAttendance(key, days);

      state = state.copyWith(
        days: days,
        summary: MonthlySummary.fromDays(days),
        loading: false,
        offline: false,
        clearError: true,
        lastSync: _cache.lastSyncAttendance(key),
      );
    } on NetworkUnavailable {
      if (stale()) return;
      if (!_loadFromCache(key)) {
        state = state.copyWith(
          loading: false,
          error:
              'You are offline and no saved data is available for this '
              'date range yet. Connect to sync.',
        );
      }
    } on ApiException catch (e) {
      if (stale()) return;
      // Try cache; if none, surface the error.
      if (!_loadFromCache(key)) {
        state = state.copyWith(loading: false, error: e.message);
      }
    } catch (e) {
      debugPrint('attendance load failed: $e');
      if (stale()) return;
      if (!_loadFromCache(key)) {
        state = state.copyWith(
          loading: false,
          error: 'Something went wrong loading attendance.',
        );
      }
    }
  }

  /// Loads cached data for [key]. Returns true if cache existed.
  bool _loadFromCache(String key) {
    final cachedDays = _cache.readAttendance(key);
    if (cachedDays == null) return false;
    state = state.copyWith(
      days: cachedDays,
      summary: MonthlySummary.fromDays(cachedDays),
      loading: false,
      offline: true,
      clearError: true,
      lastSync: _cache.lastSyncAttendance(key),
    );
    return true;
  }

  /// Pull-to-refresh handler.
  Future<void> refresh() => load(showSpinner: false);
}
