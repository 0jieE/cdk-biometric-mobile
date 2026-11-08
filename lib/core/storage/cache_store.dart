import 'package:sqflite/sqflite.dart';

import '../../models/app_notification.dart';
import '../../models/attendance_day.dart';
import '../../models/employee.dart';
import '../../models/weekly_hours.dart';

/// Offline cache backed by the app's SQLite database (see [AppDatabase] for
/// the schema).
///
/// This is the local store behind the paper's "offline data synchronization"
/// requirement: every successful network fetch writes here, and network
/// failures read back from here. Rows are converted through each model's own
/// `toJson`/`fromJson`, so the cache always parses exactly like the API.
class CacheStore {
  CacheStore(this._db);

  final Database _db;

  // sync_log resource names.
  static const _kProfile = 'profile';
  static const _kAttendancePrefix = 'attendance:'; // + start..end (YYYY-MM-DD)
  static const _kNotifications = 'notifications';
  static const _kWeekly = 'weekly';

  // ---- Profile ------------------------------------------------------------

  Future<void> saveProfile(Employee employee) async {
    final row = _employeeRow(employee);
    await _db.transaction((txn) async {
      // A different employee's cached data must not linger (their rows
      // cascade away with them).
      await txn.delete('employee', where: 'employee_no != ?',
          whereArgs: [employee.employeeNo]);
      // Update-then-insert rather than INSERT OR REPLACE: REPLACE deletes the
      // old row first, which would cascade-delete this employee's attendance.
      final updated = await txn.update('employee', row,
          where: 'employee_no = ?', whereArgs: [employee.employeeNo]);
      if (updated == 0) await txn.insert('employee', row);
      await _touch(txn, _kProfile);
    });
  }

  Future<Employee?> readProfile() async {
    final rows = await _db.query('employee', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Employee.fromJson({
      'employee_no': r['employee_no'],
      'full_name': r['full_name'],
      'first_name': r['first_name'],
      'last_name': r['last_name'],
      'department': r['department'],
      'department_code': r['department_code'],
      'date_hired': r['date_hired'],
      'is_fulltime': r['is_fulltime'] == 1,
      'employment_type': r['employment_type'],
      'username': r['username'],
      'photo_url': r['photo_url'],
    });
  }

  // ---- Attendance (one sync per date range) -------------------------------

  /// Replaces the stored days in [rangeKey]'s date range with [days], so a day
  /// the server no longer returns doesn't linger.
  Future<void> saveAttendance(String rangeKey, List<AttendanceDay> days) async {
    final (start, end) = _parseRange(rangeKey);
    await _db.transaction((txn) async {
      // Sessions go with their day (ON DELETE CASCADE).
      await txn.delete('attendance_day', where: 'date BETWEEN ? AND ?',
          whereArgs: [start, end]);
      final employeeNo = await _currentEmployeeNo(txn);
      for (final day in days) {
        final json = day.toJson();
        final dayId = await txn.insert('attendance_day', {
          'employee_no': employeeNo,
          'date': json['date'],
          'employee_type': json['employee_type'],
          'day_status': json['day_status'],
          'overtime_minutes': json['overtime_minutes'] ?? 0,
          'late_minutes': json['late_minutes'] ?? 0,
          'undertime_minutes': json['undertime_minutes'] ?? 0,
          'absent_minutes': json['absent_minutes'] ?? 0,
          'worked_minutes': json['worked_minutes'] ?? 0,
          'event': json['event'],
          'pt_time_in': json['in'],
          'pt_time_out': json['out'],
          'incomplete': json['incomplete'] == true ? 1 : 0,
          'missing': json['missing'],
        });
        for (final period in const ['am', 'pm']) {
          final session = json[period];
          if (session is! Map<String, dynamic>) continue;
          await txn.insert('attendance_session', {
            'attendance_day_id': dayId,
            'period': period.toUpperCase(),
            'time_in': session['in'],
            'time_out': session['out'],
            'status': session['status'],
            'minutes_late': session['minutes_late'] ?? 0,
            'minutes_undertime': session['minutes_undertime'] ?? 0,
            'minutes_absent': session['minutes_absent'] ?? 0,
          });
        }
      }
      await _touch(txn, '$_kAttendancePrefix$rangeKey');
    });
  }

  /// The stored days for [rangeKey], newest first (the API's order), or null
  /// if that range has never been synced.
  Future<List<AttendanceDay>?> readAttendance(String rangeKey) async {
    if (await lastSyncAttendance(rangeKey) == null) return null;
    final (start, end) = _parseRange(rangeKey);
    final dayRows = await _db.query('attendance_day',
        where: 'date BETWEEN ? AND ?', whereArgs: [start, end],
        orderBy: 'date DESC');
    if (dayRows.isEmpty) return const [];

    final ids = dayRows.map((r) => r['id']).toList();
    final sessionRows = await _db.query('attendance_session',
        where: 'attendance_day_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
    final sessions = <(Object?, String), Map<String, Object?>>{
      for (final s in sessionRows)
        (s['attendance_day_id'], s['period'] as String): s,
    };

    Map<String, dynamic>? sessionJson(Object? dayId, String period) {
      final s = sessions[(dayId, period)];
      if (s == null) return null;
      return {
        'in': s['time_in'],
        'out': s['time_out'],
        'status': s['status'],
        'minutes_late': s['minutes_late'],
        'minutes_undertime': s['minutes_undertime'],
        'minutes_absent': s['minutes_absent'],
      };
    }

    return [
      for (final r in dayRows)
        AttendanceDay.fromJson({
          'date': r['date'],
          'employee_type': r['employee_type'],
          'day_status': r['day_status'],
          'overtime_minutes': r['overtime_minutes'],
          'late_minutes': r['late_minutes'],
          'undertime_minutes': r['undertime_minutes'],
          'absent_minutes': r['absent_minutes'],
          'worked_minutes': r['worked_minutes'],
          'event': r['event'],
          'in': r['pt_time_in'],
          'out': r['pt_time_out'],
          'incomplete': r['incomplete'] == 1,
          'missing': r['missing'],
          'am': sessionJson(r['id'], 'AM'),
          'pm': sessionJson(r['id'], 'PM'),
        }),
    ];
  }

  Future<DateTime?> lastSyncAttendance(String rangeKey) =>
      lastSyncFor('$_kAttendancePrefix$rangeKey');

  // ---- Notifications ------------------------------------------------------

  Future<void> saveNotifications(List<AppNotification> notes) async {
    await _db.transaction((txn) async {
      await txn.delete('notification');
      final employeeNo = await _currentEmployeeNo(txn);
      for (final n in notes) {
        final json = n.toJson();
        await txn.insert('notification', {
          'id': json['id'],
          'employee_no': employeeNo,
          'title': json['title'],
          'body': json['body'],
          'type': json['type'],
          'is_read': json['is_read'] == true ? 1 : 0,
          'sent_at': json['sent_at'],
          'created_at': json['created_at'],
        });
      }
      await _touch(txn, _kNotifications);
    });
  }

  /// Newest first, like the API (`ordering = ['-created_at']`).
  Future<List<AppNotification>?> readNotifications() async {
    if (await lastSyncNotifications() == null) return null;
    final rows = await _db.query('notification',
        orderBy: 'created_at DESC, id DESC');
    return [
      for (final r in rows)
        AppNotification.fromJson({
          'id': r['id'],
          'title': r['title'],
          'body': r['body'],
          'type': r['type'],
          'is_read': r['is_read'] == 1,
          'sent_at': r['sent_at'],
          'created_at': r['created_at'],
        }),
    ];
  }

  Future<DateTime?> lastSyncNotifications() => lastSyncFor(_kNotifications);

  // ---- Weekly hours (part-time; the backend's default 4-week window) -------

  Future<void> saveWeekly(List<WeeklyHours> weeks) async {
    await _db.transaction((txn) async {
      await txn.delete('weekly_hours');
      final employeeNo = await _currentEmployeeNo(txn);
      for (final w in weeks) {
        await txn.insert('weekly_hours', {
          'employee_no': employeeNo,
          ...w.toJson(),
        });
      }
      await _touch(txn, _kWeekly);
    });
  }

  /// Newest week first, like the API.
  Future<List<WeeklyHours>?> readWeekly() async {
    if (await lastSyncWeekly() == null) return null;
    final rows = await _db.query('weekly_hours', orderBy: 'week_start DESC');
    return rows.map(WeeklyHours.fromJson).toList();
  }

  Future<DateTime?> lastSyncWeekly() => lastSyncFor(_kWeekly);

  // ---- Last-sync timestamps ----------------------------------------------

  Future<void> _touch(DatabaseExecutor db, String resource) => db.insert(
    'sync_log',
    {
      'resource': resource,
      'last_synced_at': DateTime.now().toUtc().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<DateTime?> lastSyncFor(String resource) async {
    final rows = await _db.query('sync_log', columns: ['last_synced_at'],
        where: 'resource = ?', whereArgs: [resource]);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_synced_at'] as String)?.toLocal();
  }

  /// Wipe all cached data (used on logout). Theme settings in `app_setting`
  /// are a device preference and are kept.
  Future<void> clear() => _db.transaction((txn) async {
    for (final table in const [
      'attendance_session',
      'attendance_day',
      'weekly_hours',
      'notification',
      'employee',
      'sync_log',
    ]) {
      await txn.delete(table);
    }
  });

  // ---- Helpers ------------------------------------------------------------

  /// The signed-in employee, for the FK on cached rows. Null only if data is
  /// cached before the profile (not a normal flow), which the nullable FK
  /// allows.
  Future<String?> _currentEmployeeNo(DatabaseExecutor db) async {
    final rows = await db.query('employee', columns: ['employee_no'], limit: 1);
    return rows.isEmpty ? null : rows.first['employee_no'] as String;
  }

  static Map<String, Object?> _employeeRow(Employee e) {
    final json = e.toJson();
    return {
      'employee_no': json['employee_no'],
      'full_name': json['full_name'],
      'first_name': json['first_name'],
      'last_name': json['last_name'],
      'department': json['department'],
      'department_code': json['department_code'],
      'date_hired': json['date_hired'],
      'is_fulltime': json['is_fulltime'] == true ? 1 : 0,
      'employment_type': json['employment_type'],
      'username': json['username'],
      'photo_url': json['photo_url'],
    };
  }

  /// `YYYY-MM-DD..YYYY-MM-DD` → (start, end).
  static (String, String) _parseRange(String rangeKey) {
    final parts = rangeKey.split('..');
    return (parts.first, parts.last);
  }
}
