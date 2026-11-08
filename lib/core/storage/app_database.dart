import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The app's local SQLite database: the offline copy of what the backend API
/// returned, plus device settings. Each table mirrors one endpoint:
///
/// | Table                | Filled from                                  |
/// |----------------------|----------------------------------------------|
/// | `employee`           | `GET /api/v1/me/`                            |
/// | `attendance_day`     | `GET /api/v1/attendance/?start=&end=`        |
/// | `attendance_session` | the `am` / `pm` objects of a full-time day   |
/// | `weekly_hours`       | `GET /api/v1/attendance/weekly/`             |
/// | `notification`       | `GET /api/v1/notifications/`                 |
/// | `sync_log`           | written by the app after each successful sync|
/// | `app_setting`        | theme preferences (kept across logout)       |
///
/// Timestamps are stored as ISO-8601 UTC text, booleans as 0/1, and enums as
/// the API's own strings (e.g. `LATE`, `PART_TIME`).
class AppDatabase {
  AppDatabase._();

  static const String fileName = 'cdk_attendance.db';
  static const int version = 1;

  /// Opens (creating on first run) the database. [path] and [factory] are for
  /// tests, which use an in-memory database through sqflite_common_ffi.
  static Future<Database> open({String? path, DatabaseFactory? factory}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        // SQLite leaves foreign keys off unless asked, per connection.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final batch = db.batch();
          for (final statement in schema) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
  }

  /// The version-1 schema. Kept as plain SQL so it can be quoted directly in
  /// the project documentation.
  static const List<String> schema = [
    '''
    CREATE TABLE employee (
      employee_no      TEXT PRIMARY KEY,
      full_name        TEXT NOT NULL,
      first_name       TEXT NOT NULL,
      last_name        TEXT NOT NULL,
      department       TEXT NOT NULL,
      department_code  TEXT NOT NULL,
      date_hired       TEXT,
      is_fulltime      INTEGER NOT NULL,
      employment_type  TEXT NOT NULL,
      username         TEXT NOT NULL,
      photo_url        TEXT
    )''',
    '''
    CREATE TABLE attendance_day (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_no        TEXT REFERENCES employee (employee_no)
                           ON DELETE CASCADE,
      date               TEXT NOT NULL,
      employee_type      TEXT NOT NULL,
      day_status         TEXT NOT NULL,
      overtime_minutes   INTEGER NOT NULL DEFAULT 0,
      late_minutes       INTEGER NOT NULL DEFAULT 0,
      undertime_minutes  INTEGER NOT NULL DEFAULT 0,
      absent_minutes     INTEGER NOT NULL DEFAULT 0,
      worked_minutes     INTEGER NOT NULL DEFAULT 0,
      event              TEXT,
      pt_time_in         TEXT,
      pt_time_out        TEXT,
      incomplete         INTEGER NOT NULL DEFAULT 0,
      missing            TEXT,
      UNIQUE (employee_no, date)
    )''',
    '''
    CREATE TABLE attendance_session (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      attendance_day_id  INTEGER NOT NULL
                           REFERENCES attendance_day (id) ON DELETE CASCADE,
      period             TEXT NOT NULL CHECK (period IN ('AM', 'PM')),
      time_in            TEXT,
      time_out           TEXT,
      status             TEXT NOT NULL,
      minutes_late       INTEGER NOT NULL DEFAULT 0,
      minutes_undertime  INTEGER NOT NULL DEFAULT 0,
      minutes_absent     INTEGER NOT NULL DEFAULT 0,
      UNIQUE (attendance_day_id, period)
    )''',
    '''
    CREATE TABLE weekly_hours (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_no        TEXT REFERENCES employee (employee_no)
                           ON DELETE CASCADE,
      week_start         TEXT NOT NULL,
      week_end           TEXT NOT NULL,
      worked_minutes     INTEGER NOT NULL DEFAULT 0,
      required_minutes   INTEGER NOT NULL DEFAULT 0,
      remaining_minutes  INTEGER NOT NULL DEFAULT 0,
      days_worked        INTEGER NOT NULL DEFAULT 0,
      required_days      INTEGER NOT NULL DEFAULT 0,
      remaining_days     INTEGER NOT NULL DEFAULT 0,
      status             TEXT NOT NULL,
      UNIQUE (employee_no, week_start)
    )''',
    '''
    CREATE TABLE notification (
      id           INTEGER PRIMARY KEY,
      employee_no  TEXT REFERENCES employee (employee_no) ON DELETE CASCADE,
      title        TEXT NOT NULL,
      body         TEXT NOT NULL,
      type         TEXT NOT NULL,
      is_read      INTEGER NOT NULL DEFAULT 0,
      sent_at      TEXT,
      created_at   TEXT
    )''',
    '''
    CREATE TABLE sync_log (
      resource        TEXT PRIMARY KEY,
      last_synced_at  TEXT NOT NULL
    )''',
    '''
    CREATE TABLE app_setting (
      key    TEXT PRIMARY KEY,
      value  TEXT NOT NULL
    )''',
    'CREATE INDEX idx_attendance_day_date ON attendance_day (date)',
    'CREATE INDEX idx_attendance_session_day '
        'ON attendance_session (attendance_day_id)',
  ];
}
