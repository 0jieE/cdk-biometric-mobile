import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/features/attendance/attendance_controller.dart';
import 'package:biometric_mobile/features/attendance/attendance_repository.dart';
import 'package:biometric_mobile/models/attendance_day.dart';

/// Repository stub that behaves as if the backend is unreachable.
class _OfflineAttendanceRepository implements AttendanceRepository {
  @override
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async =>
      throw const NetworkUnavailable();
}

void main() {
  late Directory tmp;
  late Box box;
  late CacheStore cache;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('hive_test');
    Hive.init(tmp.path);
    box = await Hive.openBox('test_cache');
    cache = CacheStore(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

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

    // Seed the cache for the range the controller defaults to.
    final key = rangeKey(container.read(attendanceControllerProvider).range);
    final cachedDays = [
      const AttendanceDay(
        date: '2026-07-01',
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
      const AttendanceDay(
        date: '2026-07-02',
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
    expect(state.days.length, 2);
    // Full-time day round-trips through the cache with its AM/PM + OT.
    expect(state.days.first.isFulltime, isTrue);
    expect(state.days.first.overtimeMinutes, 30);
    // Part-time incomplete day round-trips too.
    expect(state.days[1].incomplete, isTrue);
    expect(state.days[1].missing, 'OUT');
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
