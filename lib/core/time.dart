/// The backend stores and shows everything in Asia/Manila (UTC+8, no DST).
///
/// Attendance times arrive as UTC (`...Z`) and notification times with a
/// `+08:00` offset. Models parse both to the same exact instant (UTC); screens
/// call [toManila] just before formatting so the wall-clock shown is always
/// Manila time, whatever the phone's own timezone is.
DateTime? parseApiInstant(dynamic value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

/// Wall-clock Manila time for [instant], as a plain (non-UTC) [DateTime] so
/// `DateFormat` prints its fields as-is.
DateTime toManila(DateTime instant) {
  final m = instant.toUtc().add(const Duration(hours: 8));
  return DateTime(m.year, m.month, m.day, m.hour, m.minute, m.second);
}
