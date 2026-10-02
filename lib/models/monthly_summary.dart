import 'attendance_day.dart';

/// Counts of day statuses + total late / undertime / overtime minutes for a set
/// of days.
///
/// The app derives it from the fetched daily records so it always matches the
/// selected date range (each day carries its own `late_minutes`,
/// `undertime_minutes` and `overtime_minutes`, and their sum over a month equals
/// `GET /attendance/summary/?month=YYYY-MM`, whose JSON [MonthlySummary.fromJson]
/// can also parse).
///
/// `late` counts days whose status is LATE (both sessions attended, at least one
/// late by any number of minutes; there is no 24-hour rule). The UI folds those
/// into "Present" ([daysPresent]) and reports lateness only as minutes. A day
/// with one late session and one absent session is a HALF_DAY; its late minutes
/// are still included in [lateMinutes].
class MonthlySummary {
  final String month; // YYYY-MM
  final int present;
  final int late;
  final int halfDay;
  final int absent;
  final int overtimeMinutes;
  final int lateMinutes;
  final int undertimeMinutes;

  const MonthlySummary({
    required this.month,
    required this.present,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.overtimeMinutes,
    this.lateMinutes = 0,
    this.undertimeMinutes = 0,
  });

  /// Summary of [days]; `month` is left empty (the range is the caller's).
  factory MonthlySummary.fromDays(List<AttendanceDay> days) {
    int count(DayStatus s) => days.where((d) => d.dayStatus == s).length;
    return MonthlySummary(
      month: '',
      present: count(DayStatus.present),
      late: count(DayStatus.late),
      halfDay: count(DayStatus.halfDay),
      absent: count(DayStatus.absent),
      overtimeMinutes: days.fold(0, (sum, d) => sum + d.overtimeMinutes),
      lateMinutes: days.fold(0, (sum, d) => sum + d.lateMinutes),
      undertimeMinutes: days.fold(0, (sum, d) => sum + d.undertimeMinutes),
    );
  }

  int get total => present + late + halfDay + absent;

  /// Full days attended: on time or late. Lateness is reported in
  /// [lateMinutes], not as a separate day count.
  int get daysPresent => present + late;
  int get lostMinutes => lateMinutes + undertimeMinutes;

  factory MonthlySummary.fromJson(Map<String, dynamic> json) => MonthlySummary(
    month: (json['month'] ?? '') as String,
    present: (json['present'] as num?)?.toInt() ?? 0,
    late: (json['late'] as num?)?.toInt() ?? 0,
    halfDay: (json['half_day'] as num?)?.toInt() ?? 0,
    absent: (json['absent'] as num?)?.toInt() ?? 0,
    overtimeMinutes: (json['overtime_minutes'] as num?)?.toInt() ?? 0,
    lateMinutes: (json['late_minutes'] as num?)?.toInt() ?? 0,
    undertimeMinutes: (json['undertime_minutes'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'month': month,
    'present': present,
    'late': late,
    'half_day': halfDay,
    'absent': absent,
    'overtime_minutes': overtimeMinutes,
    'late_minutes': lateMinutes,
    'undertime_minutes': undertimeMinutes,
  };

  static const empty = MonthlySummary(
    month: '',
    present: 0,
    late: 0,
    halfDay: 0,
    absent: 0,
    overtimeMinutes: 0,
  );
}
