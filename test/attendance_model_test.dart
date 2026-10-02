import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/monthly_summary.dart';

/// These JSON blobs are copied verbatim from the live Phase 8 backend
/// (apps/api/selectors.build_daily_attendance, encoded by DRF's JSON renderer).
void main() {
  group('AttendanceDay parsing', () {
    test('full-time day with late AM/PM + overtime parses correctly', () {
      final json =
          jsonDecode('''
      {"date":"2026-07-01","employee_type":"FULL_TIME",
       "am":{"in":"2026-07-01T00:09:00Z","out":"2026-07-01T03:51:00Z","status":"LATE","minutes_late":4},
       "pm":{"in":"2026-07-01T05:14:00Z","out":"2026-07-01T09:11:00Z","status":"LATE","minutes_late":9},
       "overtime_minutes":60,"day_status":"LATE"}
      ''')
              as Map<String, dynamic>;

      final day = AttendanceDay.fromJson(json);

      expect(day.isFulltime, isTrue);
      expect(day.dayStatus, DayStatus.late);
      expect(day.am!.status, SessionStatus.late);
      expect(day.am!.minutesLate, 4);
      expect(day.pm!.status, SessionStatus.late);
      expect(day.pm!.minutesLate, 9);
      expect(day.overtimeMinutes, 60);
      expect(day.hasOvertime, isTrue);
      expect(day.am!.timeIn, isNotNull);
      expect(day.pm!.timeOut, isNotNull);
    });

    test(
      'full-time half-day parses with HALF_DAY status + one absent session',
      () {
        final json =
            jsonDecode('''
      {"date":"2026-07-03","employee_type":"FULL_TIME",
       "am":{"in":"2026-07-03T00:01:00Z","out":"2026-07-03T04:00:00Z","status":"PRESENT","minutes_late":0},
       "pm":{"in":null,"out":null,"status":"ABSENT","minutes_late":0},
       "overtime_minutes":0,"day_status":"HALF_DAY"}
      ''')
                as Map<String, dynamic>;

        final day = AttendanceDay.fromJson(json);

        expect(day.dayStatus, DayStatus.halfDay);
        expect(day.am!.status, SessionStatus.present);
        expect(day.pm!.status, SessionStatus.absent);
        expect(day.pm!.timeIn, isNull);
        expect(day.hasOvertime, isFalse);
      },
    );

    test(
      'part-time incomplete day parses with incomplete=true + missing side',
      () {
        final json =
            jsonDecode('''
      {"date":"2026-06-30","employee_type":"PART_TIME",
       "in":"2026-06-30T09:04:00Z","out":null,"day_status":"ABSENT",
       "incomplete":true,"missing":"OUT"}
      ''')
                as Map<String, dynamic>;

        final day = AttendanceDay.fromJson(json);

        expect(day.isFulltime, isFalse);
        expect(day.employeeType, EmployeeType.partTime);
        expect(day.dayStatus, DayStatus.absent);
        expect(day.incomplete, isTrue);
        expect(day.missing, 'OUT');
        expect(day.ptIn, isNotNull);
        expect(day.ptOut, isNull);
        // Full-time-only fields stay null/zero for part-time.
        expect(day.am, isNull);
        expect(day.overtimeMinutes, 0);
      },
    );

    test('a normal part-time day parses as present + complete', () {
      final json =
          jsonDecode('''
      {"date":"2026-07-02","employee_type":"PART_TIME",
       "in":"2026-07-02T00:00:00Z","out":"2026-07-02T09:11:00Z",
       "day_status":"PRESENT","incomplete":false,"missing":null}
      ''')
              as Map<String, dynamic>;

      final day = AttendanceDay.fromJson(json);
      expect(day.dayStatus, DayStatus.present);
      expect(day.incomplete, isFalse);
      expect(day.missing, isNull);
      expect(day.ptOut, isNotNull);
    });

    test('round-trips through toJson/fromJson (offline cache)', () {
      final json =
          jsonDecode('''
      {"date":"2026-07-01","employee_type":"FULL_TIME",
       "am":{"in":"2026-07-01T00:09:00Z","out":null,"status":"LATE","minutes_late":4},
       "pm":{"in":null,"out":null,"status":"ABSENT","minutes_late":0},
       "overtime_minutes":30,"day_status":"HALF_DAY"}
      ''')
              as Map<String, dynamic>;

      final day = AttendanceDay.fromJson(json);
      final round = AttendanceDay.fromJson(day.toJson());

      expect(round.employeeType, day.employeeType);
      expect(round.dayStatus, DayStatus.halfDay);
      expect(round.am!.status, SessionStatus.late);
      expect(round.am!.minutesLate, 4);
      expect(round.overtimeMinutes, 30);
    });
  });

  group('MonthlySummary parsing', () {
    test('parses present/half_day/late/absent + overtime_minutes', () {
      final json =
          jsonDecode(
                '{"month":"2026-07","present":5,"late":2,"half_day":1,"absent":3,"overtime_minutes":140}',
              )
              as Map<String, dynamic>;

      final s = MonthlySummary.fromJson(json);
      expect(s.present, 5);
      expect(s.late, 2);
      expect(s.halfDay, 1);
      expect(s.absent, 3);
      expect(s.overtimeMinutes, 140);
      expect(s.total, 11);
    });
  });
}
