/// Rich per-day attendance shape from `GET /api/v1/attendance/`.
///
/// The backend (apps/api/selectors.build_daily_attendance) returns two variants
/// discriminated by `employee_type`:
///
/// Full-time:
/// ```json
/// {"date":"2026-07-01","employee_type":"FULL_TIME",
///  "am":{"in":<iso|null>,"out":<iso|null>,"status":"PRESENT|LATE|ABSENT|PENDING",
///        "minutes_late":<int>,"minutes_undertime":<int>,"minutes_absent":<int>},
///  "pm":{...},"overtime_minutes":<int>,
///  "late_minutes":<int>,"undertime_minutes":<int>,"absent_minutes":<int>,
///  "lost_minutes":<int>, // late + undertime + absent
///  "day_status":"PRESENT|LATE|HALF_DAY|ABSENT|PENDING",
///  "event":<string, optional>} // only present on a credited special-event day
/// ```
/// `PENDING` (day or session) means "today, and the scheduled time out for that
/// session hasn't passed yet" — not yet judged, not a failure state.
///
/// A missed session loses its whole scheduled length (`minutes_absent`); a
/// whole absent day's `absent_minutes` is both sessions' scheduled length. The
/// app computes [AttendanceDay.lostMinutes] as late + undertime + absent, same
/// as the backend's `lost_minutes` (not parsed directly — see [lateMinutes]).
///
/// Part-time:
/// ```json
/// {"date":"2026-07-01","employee_type":"PART_TIME","in":<iso|null>,"out":<iso|null>,
///  "day_status":"PRESENT|PENDING|INCOMPLETE","incomplete":<bool>,"missing":"IN"|"OUT"|null,
///  "worked_minutes":<int>} // OUT - IN, no lunch deduction; 0 when incomplete
/// ```
/// A part-timer is judged on weekly hours (see `GET /attendance/weekly/` and
/// `WeeklyHours`), not a daily in/out window, so there is no PART_TIME "ABSENT"
/// any more — a day with no punches simply isn't returned at all.
///
/// Datetimes arrive as ISO-8601 UTC (`Z`) and are kept as exact instants; show
/// them with `toManila` (core/time.dart).

library;

import '../core/time.dart';

enum EmployeeType { fullTime, partTime, unknown }

EmployeeType employeeTypeFromApi(String? raw) {
  switch (raw) {
    case 'FULL_TIME':
      return EmployeeType.fullTime;
    case 'PART_TIME':
      return EmployeeType.partTime;
    default:
      return EmployeeType.unknown;
  }
}

/// Per-session (AM/PM) status. `PRESENT` = punched on time. `PENDING` = today,
/// not yet judged (the session's scheduled time out hasn't passed).
enum SessionStatus { present, late, absent, pending, unknown }

SessionStatus sessionStatusFromApi(String? raw) {
  switch (raw) {
    case 'PRESENT':
      return SessionStatus.present;
    case 'LATE':
      return SessionStatus.late;
    case 'ABSENT':
      return SessionStatus.absent;
    case 'PENDING':
      return SessionStatus.pending;
    default:
      return SessionStatus.unknown;
  }
}

String sessionStatusToApi(SessionStatus s) => switch (s) {
  SessionStatus.present => 'PRESENT',
  SessionStatus.late => 'LATE',
  SessionStatus.absent => 'ABSENT',
  SessionStatus.pending => 'PENDING',
  SessionStatus.unknown => 'UNKNOWN',
};

/// Whole-day status. `pending` = today, not yet judged. `incomplete` is a
/// PART_TIME-only day with just one of IN/OUT (counts 0 worked minutes); see
/// also [AttendanceDay.incomplete]/[AttendanceDay.missing] for which side.
enum DayStatus { present, late, halfDay, absent, pending, incomplete, unknown }

DayStatus dayStatusFromApi(String? raw) {
  switch (raw) {
    case 'PRESENT':
      return DayStatus.present;
    case 'LATE':
      return DayStatus.late;
    case 'HALF_DAY':
      return DayStatus.halfDay;
    case 'ABSENT':
      return DayStatus.absent;
    case 'PENDING':
      return DayStatus.pending;
    case 'INCOMPLETE':
      return DayStatus.incomplete;
    default:
      return DayStatus.unknown;
  }
}

String dayStatusToApi(DayStatus s) => switch (s) {
  DayStatus.present => 'PRESENT',
  DayStatus.late => 'LATE',
  DayStatus.halfDay => 'HALF_DAY',
  DayStatus.absent => 'ABSENT',
  DayStatus.pending => 'PENDING',
  DayStatus.incomplete => 'INCOMPLETE',
  DayStatus.unknown => 'UNKNOWN',
};

DateTime? _parseDate(dynamic value) => parseApiInstant(value);

/// One AM or PM work session for a full-time employee.
class AttendanceSession {
  final DateTime? timeIn;
  final DateTime? timeOut;
  final SessionStatus status;
  final int minutesLate;

  /// Minutes left early (clocked out before the scheduled end), and minutes
  /// lost to a missed session entirely (its whole scheduled length). Parsed
  /// for completeness; the day-level totals ([AttendanceDay.undertimeMinutes],
  /// [AttendanceDay.absentMinutes]) are what the summary card uses.
  final int minutesUndertime;
  final int minutesAbsent;

  const AttendanceSession({
    required this.timeIn,
    required this.timeOut,
    required this.status,
    required this.minutesLate,
    this.minutesUndertime = 0,
    this.minutesAbsent = 0,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) =>
      AttendanceSession(
        timeIn: _parseDate(json['in']),
        timeOut: _parseDate(json['out']),
        status: sessionStatusFromApi(json['status'] as String?),
        minutesLate: (json['minutes_late'] as num?)?.toInt() ?? 0,
        minutesUndertime: (json['minutes_undertime'] as num?)?.toInt() ?? 0,
        minutesAbsent: (json['minutes_absent'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'in': timeIn?.toIso8601String(),
    'out': timeOut?.toIso8601String(),
    'status': sessionStatusToApi(status),
    'minutes_late': minutesLate,
    'minutes_undertime': minutesUndertime,
    'minutes_absent': minutesAbsent,
  };
}

class AttendanceDay {
  final String date; // YYYY-MM-DD
  final EmployeeType employeeType;
  final DayStatus dayStatus;

  // Full-time only.
  final AttendanceSession? am;
  final AttendanceSession? pm;
  final int overtimeMinutes;

  /// Whole-day totals (AM + PM) for full-time days: minutes late, minutes left
  /// early ("undertime"), and minutes lost to missed sessions ("absent" — a
  /// whole missed day is both sessions' scheduled length, e.g. 480).
  final int lateMinutes;
  final int undertimeMinutes;
  final int absentMinutes;

  /// Set only on a credited special-event day (admin-required AM/PM punches on
  /// a Special holiday, fully completed) — e.g. "Foundation Day (AM required)".
  /// `dayStatus` is already PRESENT on such a day; this is purely informational.
  final String? event;

  // Part-time only.
  final DateTime? ptIn;
  final DateTime? ptOut;
  final bool incomplete;
  final String? missing; // 'IN' | 'OUT' | null

  /// Minutes actually worked (OUT - IN, no lunch deduction); 0 when
  /// [incomplete]. Part-timers are judged on weekly totals of this, not a
  /// daily window — see `GET /attendance/weekly/`.
  final int workedMinutes;

  const AttendanceDay({
    required this.date,
    required this.employeeType,
    required this.dayStatus,
    this.am,
    this.pm,
    this.overtimeMinutes = 0,
    this.lateMinutes = 0,
    this.undertimeMinutes = 0,
    this.absentMinutes = 0,
    this.event,
    this.ptIn,
    this.ptOut,
    this.incomplete = false,
    this.missing,
    this.workedMinutes = 0,
  });

  bool get isFulltime => employeeType == EmployeeType.fullTime;
  bool get hasOvertime => overtimeMinutes > 0;

  /// Late + undertime + absent minutes — matches the backend's `lost_minutes`.
  int get lostMinutes => lateMinutes + undertimeMinutes + absentMinutes;

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    final type = employeeTypeFromApi(json['employee_type'] as String?);
    final dayStatus = dayStatusFromApi(json['day_status'] as String?);

    if (type == EmployeeType.partTime) {
      return AttendanceDay(
        date: (json['date'] ?? '') as String,
        employeeType: type,
        dayStatus: dayStatus,
        ptIn: _parseDate(json['in']),
        ptOut: _parseDate(json['out']),
        incomplete: (json['incomplete'] ?? false) as bool,
        missing: json['missing'] as String?,
        workedMinutes: (json['worked_minutes'] as num?)?.toInt() ?? 0,
      );
    }

    // Full-time (default). `am`/`pm` are nested objects.
    final amJson = json['am'];
    final pmJson = json['pm'];
    return AttendanceDay(
      date: (json['date'] ?? '') as String,
      employeeType: type == EmployeeType.unknown ? EmployeeType.fullTime : type,
      dayStatus: dayStatus,
      am: amJson is Map
          ? AttendanceSession.fromJson(Map<String, dynamic>.from(amJson))
          : null,
      pm: pmJson is Map
          ? AttendanceSession.fromJson(Map<String, dynamic>.from(pmJson))
          : null,
      overtimeMinutes: (json['overtime_minutes'] as num?)?.toInt() ?? 0,
      lateMinutes: (json['late_minutes'] as num?)?.toInt() ?? 0,
      undertimeMinutes: (json['undertime_minutes'] as num?)?.toInt() ?? 0,
      absentMinutes: (json['absent_minutes'] as num?)?.toInt() ?? 0,
      event: json['event'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final base = <String, dynamic>{
      'date': date,
      'employee_type': switch (employeeType) {
        EmployeeType.fullTime => 'FULL_TIME',
        EmployeeType.partTime => 'PART_TIME',
        EmployeeType.unknown => 'UNKNOWN',
      },
      'day_status': dayStatusToApi(dayStatus),
    };
    if (employeeType == EmployeeType.partTime) {
      base.addAll({
        'in': ptIn?.toIso8601String(),
        'out': ptOut?.toIso8601String(),
        'incomplete': incomplete,
        'missing': missing,
        'worked_minutes': workedMinutes,
      });
    } else {
      base.addAll({
        'am': am?.toJson(),
        'pm': pm?.toJson(),
        'overtime_minutes': overtimeMinutes,
        'late_minutes': lateMinutes,
        'undertime_minutes': undertimeMinutes,
        'absent_minutes': absentMinutes,
        if (event != null) 'event': event,
      });
    }
    return base;
  }
}
