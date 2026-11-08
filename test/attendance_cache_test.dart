import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/features/attendance/attendance_controller.dart';
import 'package:biometric_mobile/features/attendance/attendance_repository.dart';
import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/weekly_hours.dart';

import 'helpers.dart';

/// Repository stub that behaves as if the backend is unreachable.
class _OfflineAttendanceRepository implements AttendanceRepository {
  @override
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async =>
      throw const NetworkUnavailable();

  @override
  Future<List<WeeklyHours>> fetchWeekly({DateTime? start, DateTime? end}) async =>
      throw const NetworkUnavailable();
}

void main() {
  late Database db;
  late CacheStore cache;

  setUp(() async {
    db = await openTestDatabase();
    cache = CacheStore(db);
  });

  tearDown(() => db.close());

  test('attendance load falls back to cached data on network error', () async {
    final container = ProviderContainer(
      overrides: [
        cacheStoreProvider.overrideWithValue(cache),
        attendanceRepositoryProvider.overrideWithValue(
          _OfflineAttendanceRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Seed the cache for the range the controller defaults to, with two days
    // inside it (the cache only returns days within the requested range).
    final range = container.read(attendanceControllerProvider).range;
    final key = rangeKey(range);
    final first = formatApiDate(range.start);
    final second = formatApiDate(range.start.add(const Duration(days: 1)));
    final cachedDays = [
      AttendanceDay(
        date: first,
        employeeType: EmployeeType.fullTime,
        dayStatus: DayStatus.present,
        am: AttendanceSession(
          timeIn: null,
          timeOut: null,
          status: SessionStatus.present,
          minutesLate: 0,
        ),
        pm: AttendanceSession(
          timeIn: null,
          timeOut: null,
          status: SessionStatus.present,
          minutesLate: 0,
        ),
        overtimeMinutes: 30,
      ),
      AttendanceDay(
        date: second,
        employeeType: EmployeeType.partTime,
        dayStatus: DayStatus.absent,
        ptIn: null,
        ptOut: null,
        incomplete: true,
        missing: 'OUT',
      ),
    ];
    await cache.saveAttendance(key, cachedDays);

    // Act: the network fails, so the controller should serve the cache.
    await container.read(attendanceControllerProvider.notifier).load();

    final state = container.read(attendanceControllerProvider);
    expect(state.offline, isTrue, reason: 'offline banner should be flagged');
    expect(state.error, isNull);
    // Newest first, like the API.
    expect(state.days.map((d) => d.date), [second, first]);
    // Full-time day round-trips through the cache with its AM/PM + OT.
    final fullTime = state.days[1];
    expect(fullTime.isFulltime, isTrue);
    expect(fullTime.overtimeMinutes, 30);
    expect(fullTime.am?.status, SessionStatus.present);
    expect(fullTime.pm?.status, SessionStatus.present);
    // Part-time incomplete day round-trips too.
    expect(state.days[0].incomplete, isTrue);
    expect(state.days[0].missing, 'OUT');
    // The summary is derived from the cached days.
    expect(state.summary.present, 1);
    expect(state.summary.absent, 1);
    expect(state.summary.overtimeMinutes, 30);
  });

  test('with no cache and a network error, surfaces an error state', () async {
    final container = ProviderContainer(
      overrides: [
        cacheStoreProvider.overrideWithValue(cache),
        attendanceRepositoryProvider.overrideWithValue(
          _OfflineAttendanceRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(attendanceControllerProvider.notifier).load();

    final state = container.read(attendanceControllerProvider);
    expect(state.offline, isFalse);
    expect(state.isEmpty, isTrue);
  });
}
