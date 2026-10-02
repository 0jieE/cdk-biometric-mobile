/// Rich per-day attendance shape from `GET /api/v1/attendance/` (Phase 8/9).
///
/// The backend (apps/api/selectors.build_daily_attendance) returns two variants
/// discriminated by `employee_type`:
///
/// Full-time:
/// ```json
/// {"date":"2026-07-01","employee_type":"FULL_TIME",
///  "am":{"in":<iso|null>,"out":<iso|null>,"status":"PRESENT|LATE|ABSENT","minutes_late":<int>},
///  "pm":{...},"overtime_minutes":<int>,"day_status":"PRESENT|LATE|HALF_DAY|ABSENT"}
/// ```
/// Part-time:
/// ```json
/// {"date":"2026-07-01","employee_type":"PART_TIME","in":<iso|null>,"out":<iso|null>,
///  "day_status":"PRESENT|ABSENT","incomplete":<bool>,"missing":"IN"|"OUT"|null}
/// ```
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

/// Per-session (AM/PM) status. `PRESENT` = punched on time.
enum SessionStatus { present, late, absent, unknown }

SessionStatus sessionStatusFromApi(String? raw) {
  switch (raw) {
    case 'PRESENT':
      return SessionStatus.present;
    case 'LATE':
      return SessionStatus.late;
    case 'ABSENT':
      return SessionStatus.absent;
    default:
      return SessionStatus.unknown;
  }
}

String sessionStatusToApi(SessionStatus s) => switch (s) {
  SessionStatus.present => 'PRESENT',
  SessionStatus.late => 'LATE',
  SessionStatus.absent => 'ABSENT',
  SessionStatus.unknown => 'UNKNOWN',
};

/// Whole-day status.
enum DayStatus { present, late, halfDay, absent, unknown }

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
    default:
      return DayStatus.unknown;
  }
}

String dayStatusToApi(DayStatus s) => switch (s) {
  DayStatus.present => 'PRESENT',
  DayStatus.late => 'LATE',
  DayStatus.halfDay => 'HALF_DAY',
  DayStatus.absent => 'ABSENT',
  DayStatus.unknown => 'UNKNOWN',
};

DateTime? _parseDate(dynamic value) => parseApiInstant(value);

/// One AM or PM work session for a full-time employee.
class AttendanceSession {
  final DateTime? timeIn;
  final DateTime? timeOut;
  final SessionStatus status;
  final int minutesLate;

  const AttendanceSession({
    required this.timeIn,
    required this.timeOut,
    required this.status,
    required this.minutesLate,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) =>
      AttendanceSession(
        timeIn: _parseDate(json['in']),
        timeOut: _parseDate(json['out']),
        status: sessionStatusFromApi(json['status'] as String?),
        minutesLate: (json['minutes_late'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'in': timeIn?.toIso8601String(),
    'out': timeOut?.toIso8601String(),
    'status': sessionStatusToApi(status),
    'minutes_late': minutesLate,
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

  /// Whole-day totals (AM + PM) for full-time days: minutes late, and minutes
  /// left early ("undertime"). The backend's `lost_minutes` is their sum.
  final int lateMinutes;
  final int undertimeMinutes;

  // Part-time only.
  final DateTime? ptIn;
  final DateTime? ptOut;
  final bool incomplete;
  final String? missing; // 'IN' | 'OUT' | null

  const AttendanceDay({
    required this.date,
    required this.employeeType,
    required this.dayStatus,
    this.am,
    this.pm,
    this.overtimeMinutes = 0,
    this.lateMinutes = 0,
    this.undertimeMinutes = 0,
    this.ptIn,
    this.ptOut,
    this.incomplete = false,
    this.missing,
  });

  bool get isFulltime => employeeType == EmployeeType.fullTime;
  bool get hasOvertime => overtimeMinutes > 0;
  int get lostMinutes => lateMinutes + undertimeMinutes;

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
      });
    } else {
      base.addAll({
        'am': am?.toJson(),
        'pm': pm?.toJson(),
        'overtime_minutes': overtimeMinutes,
        'late_minutes': lateMinutes,
        'undertime_minutes': undertimeMinutes,
      });
    }
    return base;
  }
}
