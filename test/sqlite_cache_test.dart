import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/core/storage/settings_store.dart';
import 'package:biometric_mobile/models/app_notification.dart';
import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/employee.dart';
import 'package:biometric_mobile/models/weekly_hours.dart';

import 'helpers.dart';

const _employee = Employee(
  employeeNo: 'EMP-1002',
  fullName: 'Jose Reyes',
  firstName: 'Jose',
  lastName: 'Reyes',
  department: 'Human Resources',
  departmentCode: 'HR',
  dateHired: '2020-06-01',
  username: 'jose',
);

/// Full-time day in the live API shape (late AM, absent PM, an event note).
AttendanceDay _fullTimeDay(String date) => AttendanceDay.fromJson({
  'date': date,
  'employee_type': 'FULL_TIME',
  'am': {
    'in': '${date}T00:09:00Z',
    'out': '${date}T04:00:00Z',
    'status': 'LATE',
    'minutes_late': 9,
    'minutes_undertime': 0,
    'minutes_absent': 0,
  },
  'pm': {
    'in': null,
    'out': null,
    'status': 'ABSENT',
    'minutes_late': 0,
    'minutes_undertime': 0,
    'minutes_absent': 240,
  },
  'overtime_minutes': 15,
  'late_minutes': 9,
  'undertime_minutes': 0,
  'absent_minutes': 240,
  'lost_minutes': 249,
  'day_status': 'HALF_DAY',
  'event': 'Foundation Day',
});

void main() {
  late Database db;
  late CacheStore cache;

  setUp(() async {
    db = await openTestDatabase();
    cache = CacheStore(db);
  });

  tearDown(() => db.close());

  test('creates every table from the endpoint-based schema', () async {
    final rows = await db.query('sqlite_master',
        columns: ['name'], where: "type = 'table'");
    expect(
      rows.map((r) => r['name']),
      containsAll([
        'employee',
        'attendance_day',
        'attendance_session',
        'weekly_hours',
        'notification',
        'sync_log',
        'app_setting',
      ]),
    );
  });

  test('profile round-trips through the employee table', () async {
    await cache.saveProfile(_employee);
    final back = await cache.readProfile();
    expect(back?.employeeNo, 'EMP-1002');
    expect(back?.username, 'jose');
    expect(back?.isFulltime, isTrue);
    expect(back?.dateHired, '2020-06-01');
  });

  test('a full-time day and its AM/PM sessions round-trip, linked by FK',
      () async {
    await cache.saveProfile(_employee);
    await cache.saveAttendance('2026-09-01..2026-09-30', [
      _fullTimeDay('2026-09-18'),
    ]);

    final days = await cache.readAttendance('2026-09-01..2026-09-30');
    final day = days!.single;
    expect(day.dayStatus, DayStatus.halfDay);
    expect(day.event, 'Foundation Day');
    expect(day.overtimeMinutes, 15);
    expect(day.absentMinutes, 240);
    expect(day.am?.status, SessionStatus.late);
    expect(day.am?.minutesLate, 9);
    expect(day.am?.timeIn, DateTime.utc(2026, 9, 18, 0, 9));
    expect(day.pm?.status, SessionStatus.absent);
    expect(day.pm?.minutesAbsent, 240);

    final dayRow = (await db.query('attendance_day')).single;
    expect(dayRow['employee_no'], 'EMP-1002');
    final sessionRows = await db.query('attendance_session');
    expect(sessionRows.map((r) => r['period']), unorderedEquals(['AM', 'PM']));
    expect(sessionRows.every((r) => r['attendance_day_id'] == dayRow['id']),
        isTrue);
  });

  test('a part-time day round-trips its single IN/OUT and worked minutes',
      () async {
    await cache.saveAttendance('2026-09-15..2026-09-15', [
      AttendanceDay.fromJson({
        'date': '2026-09-15',
        'employee_type': 'PART_TIME',
        'in': '2026-09-15T09:01:00Z',
        'out': null,
        'incomplete': true,
        'missing': 'OUT',
        'worked_minutes': 0,
        'day_status': 'INCOMPLETE',
      }),
    ]);
    final day = (await cache.readAttendance('2026-09-15..2026-09-15'))!.single;
    expect(day.isFulltime, isFalse);
    expect(day.dayStatus, DayStatus.incomplete);
    expect(day.ptIn, DateTime.utc(2026, 9, 15, 9, 1));
    expect(day.missing, 'OUT');
    expect(await db.query('attendance_session'), isEmpty);
  });

  test('re-syncing a range replaces it: a day the server dropped is removed, '
      'and its sessions cascade away', () async {
    const range = '2026-09-01..2026-09-30';
    await cache.saveAttendance(range, [
      _fullTimeDay('2026-09-18'),
      _fullTimeDay('2026-09-17'),
    ]);
    await cache.saveAttendance(range, [_fullTimeDay('2026-09-18')]);

    final days = await cache.readAttendance(range);
    expect(days!.map((d) => d.date), ['2026-09-18']);
    expect((await db.query('attendance_session')).length, 2);
  });

  test('a range that was never synced reads as null (not an empty list)',
      () async {
    await cache.saveAttendance('2026-09-01..2026-09-30', const []);
    expect(await cache.readAttendance('2026-09-01..2026-09-30'), isEmpty);
    expect(await cache.readAttendance('2026-10-01..2026-10-31'), isNull);
  });

  test('changing the username updates the profile without deleting the '
      'cached attendance (no REPLACE cascade)', () async {
    await cache.saveProfile(_employee);
    await cache.saveAttendance('2026-09-01..2026-09-30', [
      _fullTimeDay('2026-09-18'),
    ]);

    await cache.saveProfile(_employee.copyWith(username: 'jreyes'));

    expect((await cache.readProfile())?.username, 'jreyes');
    expect(await cache.readAttendance('2026-09-01..2026-09-30'), hasLength(1));
  });

  test('saving a different employee removes the previous one\'s rows',
      () async {
    await cache.saveProfile(_employee);
    await cache.saveAttendance('2026-09-01..2026-09-30', [
      _fullTimeDay('2026-09-18'),
    ]);

    await cache.saveProfile(const Employee(
      employeeNo: 'EMP-1007',
      fullName: 'Grace Villanueva',
      firstName: 'Grace',
      lastName: 'Villanueva',
      department: 'College Faculty',
      departmentCode: 'CF',
      isFulltime: false,
    ));

    expect(await db.query('attendance_day'), isEmpty);
    expect(await db.query('attendance_session'), isEmpty);
  });

  test('notifications come back newest first with their read state', () async {
    await cache.saveProfile(_employee);
    await cache.saveNotifications([
      AppNotification.fromJson({
        'id': 7,
        'title': 'Time in',
        'body': 'AM in recorded',
        'type': 'PUNCH',
        'is_read': false,
        'sent_at': '2026-11-02T00:05:00Z',
        'created_at': '2026-11-02T00:05:00Z',
      }),
      AppNotification.fromJson({
        'id': 8,
        'title': 'Time out',
        'body': 'PM out recorded',
        'type': 'PUNCH',
        'is_read': true,
        'sent_at': '2026-11-02T09:00:00Z',
        'created_at': '2026-11-02T09:00:00Z',
      }),
    ]);

    final notes = await cache.readNotifications();
    expect(notes!.map((n) => n.id), [8, 7]);
    expect(notes.first.isRead, isTrue);
    expect(notes.last.isRead, isFalse);
  });

  test('weekly hours come back newest week first', () async {
    await cache.saveWeekly([
      for (final start in ['2026-09-07', '2026-09-14'])
        WeeklyHours.fromJson({
          'week_start': start,
          'week_end': start,
          'worked_minutes': 90,
          'required_minutes': 180,
          'remaining_minutes': 90,
          'days_worked': 1,
          'required_days': 2,
          'remaining_days': 1,
          'status': 'SHORT',
        }),
    ]);
    final weeks = await cache.readWeekly();
    expect(weeks!.map((w) => w.weekStart), ['2026-09-14', '2026-09-07']);
    expect(weeks.first.requiredDays, 2);
  });

  test('each sync records a last-sync time in sync_log', () async {
    expect(await cache.lastSyncWeekly(), isNull);
    await cache.saveWeekly(const []);
    final at = await cache.lastSyncWeekly();
    expect(at, isNotNull);
    expect(DateTime.now().difference(at!).inMinutes, lessThan(1));
  });

  test('logout clear() empties the cache but keeps theme settings', () async {
    final settings = await SqliteSettingsStore.open(db);
    await settings.saveAccent('teal');
    await cache.saveProfile(_employee);
    await cache.saveAttendance('2026-09-01..2026-09-30', [
      _fullTimeDay('2026-09-18'),
    ]);
    await cache.saveWeekly(const []);

    await cache.clear();

    for (final table in const [
      'employee',
      'attendance_day',
      'attendance_session',
      'weekly_hours',
      'notification',
      'sync_log',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    expect((await SqliteSettingsStore.open(db)).readAccent(), 'teal');
  });

  test('foreign keys are enforced', () async {
    expect(
      () => db.insert('attendance_session', {
        'attendance_day_id': 999,
        'period': 'AM',
        'status': 'PRESENT',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('settings persist and are readable synchronously after reopen',
      () async {
    final settings = await SqliteSettingsStore.open(db);
    expect(settings.readThemeMode(), isNull);
    await settings.saveThemeMode('dark');
    await settings.saveThemeMode('light');
    expect(settings.readThemeMode(), 'light');
    expect((await SqliteSettingsStore.open(db)).readThemeMode(), 'light');
  });
}
