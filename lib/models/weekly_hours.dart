/// One Monday-to-Sunday week's hours for a part-time employee, from
/// `GET /api/v1/attendance/weekly/?start=&end=` (both optional; default is the
/// last 4 weeks ending today). Full-timers always get an empty `results` list —
/// they're judged per session/day, not weekly.
///
/// ```json
/// {"week_start":"2026-09-28","week_end":"2026-10-04","worked_minutes":2161,
///  "required_minutes":1200,"remaining_minutes":0,"days_worked":5,
///  "required_days":2,"remaining_days":0,"status":"MET"}
/// ```
/// `required_minutes` comes from the employee's weekly-hours override, or the
/// default set on the web Schedule page. `required_days` is a global admin
/// setting (default 2). `days_worked` counts only complete days (both IN and
/// OUT). Weeks before the employee's tracking began are omitted.
library;

enum WeekStatus {
  /// Worked >= required minutes AND on >= required days. Enough hours on too
  /// few days is NOT met — always trust `status`, never infer it from hours.
  met,

  /// The week isn't over yet and the requirement isn't met yet.
  inProgress,

  /// The week is over and the requirement wasn't met.
  short,
  unknown,
}

WeekStatus weekStatusFromApi(String? raw) {
  switch (raw) {
    case 'MET':
      return WeekStatus.met;
    case 'IN_PROGRESS':
      return WeekStatus.inProgress;
    case 'SHORT':
      return WeekStatus.short;
    default:
      return WeekStatus.unknown;
  }
}

String weekStatusToApi(WeekStatus s) => switch (s) {
  WeekStatus.met => 'MET',
  WeekStatus.inProgress => 'IN_PROGRESS',
  WeekStatus.short => 'SHORT',
  WeekStatus.unknown => 'UNKNOWN',
};

class WeeklyHours {
  final String weekStart; // YYYY-MM-DD, a Monday
  final String weekEnd; // YYYY-MM-DD, the following Sunday
  final int workedMinutes;
  final int requiredMinutes;
  final int remainingMinutes;
  final int daysWorked;

  /// 0 when the backend (or an older cached entry) didn't send it.
  final int requiredDays;
  final int remainingDays;
  final WeekStatus status;

  const WeeklyHours({
    required this.weekStart,
    required this.weekEnd,
    required this.workedMinutes,
    required this.requiredMinutes,
    required this.remainingMinutes,
    required this.daysWorked,
    this.requiredDays = 0,
    this.remainingDays = 0,
    required this.status,
  });

  /// `requiredMinutes` is never 0 in practice (a schedule always sets some
  /// requirement), but this guards the progress-bar math just in case.
  double get fraction => requiredMinutes <= 0
      ? (workedMinutes > 0 ? 1.0 : 0.0)
      : (workedMinutes / requiredMinutes).clamp(0.0, 1.0);

  factory WeeklyHours.fromJson(Map<String, dynamic> json) => WeeklyHours(
    weekStart: (json['week_start'] ?? '') as String,
    weekEnd: (json['week_end'] ?? '') as String,
    workedMinutes: (json['worked_minutes'] as num?)?.toInt() ?? 0,
    requiredMinutes: (json['required_minutes'] as num?)?.toInt() ?? 0,
    remainingMinutes: (json['remaining_minutes'] as num?)?.toInt() ?? 0,
    daysWorked: (json['days_worked'] as num?)?.toInt() ?? 0,
    requiredDays: (json['required_days'] as num?)?.toInt() ?? 0,
    remainingDays: (json['remaining_days'] as num?)?.toInt() ?? 0,
    status: weekStatusFromApi(json['status'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'week_start': weekStart,
    'week_end': weekEnd,
    'worked_minutes': workedMinutes,
    'required_minutes': requiredMinutes,
    'remaining_minutes': remainingMinutes,
    'days_worked': daysWorked,
    'required_days': requiredDays,
    'remaining_days': remainingDays,
    'status': weekStatusToApi(status),
  };
}
