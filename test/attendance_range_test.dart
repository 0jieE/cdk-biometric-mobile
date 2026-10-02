import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/features/attendance/attendance_controller.dart';
import 'package:biometric_mobile/features/attendance/attendance_repository.dart';
import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/monthly_summary.dart';

AttendanceDay _day(String date, DayStatus status, {int ot = 0}) =>
    AttendanceDay(
      date: date,
      employeeType: EmployeeType.fullTime,
      dayStatus: status,
      overtimeMinutes: ot,
    );

/// Serves the days that fall inside the requested range from a fixed list, and
/// records what was asked for.
class _RangeRepo implements AttendanceRepository {
  _RangeRepo(this.all);
  final List<AttendanceDay> all;
  final requests = <(String, String)>[];

  @override
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async {
    final s = formatApiDate(start), e = formatApiDate(end);
    requests.add((s, e));
    return all
        .where((d) => d.date.compareTo(s) >= 0 && d.date.compareTo(e) <= 0)
        .toList();
  }
}

class _NoopCache implements CacheStore {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('read') || name.contains('lastSync')) return null;
    return Future<void>.value();
  }
}

void main() {
  final days = [
    _day('2026-07-01', DayStatus.present, ot: 30),
    _day('2026-07-02', DayStatus.late),
    _day('2026-07-03', DayStatus.halfDay),
    _day('2026-07-10', DayStatus.absent),
    _day('2026-07-11', DayStatus.present, ot: 15),
  ];

  test('MonthlySummary.fromDays counts statuses and sums overtime', () {
    final s = MonthlySummary.fromDays(days);
    expect(
      (s.present, s.late, s.halfDay, s.absent, s.overtimeMinutes),
      (2, 1, 1, 1, 45),
    );
  });

  test(
    'selecting a date range loads it and summarises only that range',
    () async {
      final repo = _RangeRepo(days);
      final container = ProviderContainer(
        overrides: [
          cacheStoreProvider.overrideWithValue(_NoopCache()),
          attendanceRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(attendanceControllerProvider.notifier)
          .selectRange(
            DateTimeRange(
              start: DateTime(2026, 7, 1),
              end: DateTime(2026, 7, 3),
            ),
          );

      var state = container.read(attendanceControllerProvider);
      expect(repo.requests.last, ('2026-07-01', '2026-07-03'));
      expect(state.days.length, 3);
      expect(state.summary.present, 1);
      expect(state.summary.late, 1);
      expect(state.summary.halfDay, 1);
      expect(state.summary.absent, 0);
      expect(state.summary.overtimeMinutes, 30);

      // A different range gives a different summary.
      await container
          .read(attendanceControllerProvider.notifier)
          .selectRange(
            DateTimeRange(
              start: DateTime(2026, 7, 10),
              end: DateTime(2026, 7, 11),
            ),
          );
      state = container.read(attendanceControllerProvider);
      expect(state.days.length, 2);
      expect(state.summary.absent, 1);
      expect(state.summary.present, 1);
      expect(state.summary.overtimeMinutes, 15);
    },
  );

  test('summary totals late / undertime minutes from the daily records', () {
    // Shapes copied from the live API (emp-1004, Sept 2026).
    final live = [
      {
        'date': '2026-09-18',
        'employee_type': 'FULL_TIME',
        'day_status': 'LATE',
        'am': {
          'in': null,
          'out': null,
          'status': 'LATE',
          'minutes_late': 12,
          'minutes_undertime': 0,
        },
        'pm': {
          'in': null,
          'out': null,
          'status': 'LATE',
          'minutes_late': 14,
          'minutes_undertime': 0,
        },
        'overtime_minutes': 0,
        'late_minutes': 26,
        'undertime_minutes': 0,
        'lost_minutes': 26,
      },
      {
        'date': '2026-09-17',
        'employee_type': 'FULL_TIME',
        'day_status': 'LATE',
        'am': {
          'in': null,
          'out': null,
          'status': 'LATE',
          'minutes_late': 8,
          'minutes_undertime': 0,
        },
        'pm': {
          'in': null,
          'out': null,
          'status': 'LATE',
          'minutes_late': 7,
          'minutes_undertime': 1,
        },
        'overtime_minutes': 0,
        'late_minutes': 15,
        'undertime_minutes': 1,
        'lost_minutes': 16,
      },
      // One late session + one absent session is a HALF_DAY: its late minutes
      // count toward the total but the day is not in the "late" day count.
      {
        'date': '2026-09-01',
        'employee_type': 'FULL_TIME',
        'day_status': 'HALF_DAY',
        'am': {
          'in': null,
          'out': null,
          'status': 'LATE',
          'minutes_late': 13,
          'minutes_undertime': 1,
        },
        'pm': {
          'in': null,
          'out': null,
          'status': 'ABSENT',
          'minutes_late': 0,
          'minutes_undertime': 0,
        },
        'overtime_minutes': 0,
        'late_minutes': 13,
        'undertime_minutes': 1,
        'lost_minutes': 14,
      },
    ].map(AttendanceDay.fromJson).toList();

    final s = MonthlySummary.fromDays(live);

    expect(s.late, 2, reason: 'two days are LATE');
    expect(s.daysPresent, 2, reason: 'late days count as present days');
    expect(s.halfDay, 1);
    expect(s.lateMinutes, 26 + 15 + 13);
    expect(s.undertimeMinutes, 0 + 1 + 1);
    expect(s.lostMinutes, 54 + 2);
    expect(live.first.lostMinutes, 26);
    // Survives the offline cache round trip.
    final again = AttendanceDay.fromJson(live[1].toJson());
    expect((again.lateMinutes, again.undertimeMinutes), (15, 1));
  });
}
