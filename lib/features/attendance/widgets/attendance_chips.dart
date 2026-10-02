import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/attendance_day.dart';

/// Attendance status palette (shared with the summary tiles). These are the
/// Phase 11 semantic colors and are intentionally NOT re-themed by the accent.
class StatusColors {
  StatusColors._();
  static const present = AppTheme.present; // green
  static const late = AppTheme.late; // orange
  static const halfDay = AppTheme.halfDay; // amber
  static const absent = AppTheme.absent; // red
  static const overtime = AppTheme.overtime; // blue
  static const missing = AppTheme.absent; // red
  static const unknown = Colors.grey;
}

/// Minutes → "Xh Ym" (or "Ym" under an hour). 0 → "0m".
String formatMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

Widget _pill({
  required Key? key,
  required Color color,
  required IconData icon,
  required String label,
  bool filled = false,
}) {
  return Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: filled ? Colors.white : color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: filled ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

/// Whole-day status badge shown at the card header.
class DayStatusBadge extends StatelessWidget {
  const DayStatusBadge({super.key, required this.status});
  final DayStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      DayStatus.present => (
        StatusColors.present,
        'Present',
        Icons.check_circle,
      ),
      DayStatus.late => (StatusColors.late, 'Late', Icons.schedule),
      DayStatus.halfDay => (
        StatusColors.halfDay,
        'Half-day',
        Icons.hourglass_bottom,
      ),
      DayStatus.absent => (StatusColors.absent, 'Absent', Icons.cancel),
      DayStatus.unknown => (
        StatusColors.unknown,
        'Unknown',
        Icons.help_outline,
      ),
    };
    return _pill(
      key: ValueKey('day-${dayStatusToApi(status)}'),
      color: color,
      icon: icon,
      label: label,
      filled: true,
    );
  }
}

/// Per-session (AM/PM) chip: green on-time, orange late "+Nm", red missing.
class SessionChip extends StatelessWidget {
  const SessionChip({super.key, required this.status, this.minutesLate = 0});
  final SessionStatus status;
  final int minutesLate;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      SessionStatus.present => (
        StatusColors.present,
        'On time',
        Icons.check_circle_outline,
      ),
      SessionStatus.late => (
        StatusColors.late,
        minutesLate > 0 ? 'Late +${minutesLate}m' : 'Late',
        Icons.schedule,
      ),
      SessionStatus.absent => (
        StatusColors.missing,
        'Missing',
        Icons.cancel_outlined,
      ),
      SessionStatus.unknown => (
        StatusColors.unknown,
        'Unknown',
        Icons.help_outline,
      ),
    };
    return _pill(
      key: ValueKey('session-${sessionStatusToApi(status)}'),
      color: color,
      icon: icon,
      label: label,
    );
  }
}

/// "OT: Xh Ym" badge (only render when minutes > 0).
class OvertimeBadge extends StatelessWidget {
  const OvertimeBadge({super.key, required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return _pill(
      key: const ValueKey('ot-badge'),
      color: StatusColors.overtime,
      icon: Icons.more_time,
      label: 'OT ${formatMinutes(minutes)}',
    );
  }
}

/// Warning chip for a part-time incomplete day: "Incomplete — missing OUT".
class IncompleteChip extends StatelessWidget {
  const IncompleteChip({super.key, required this.missing});
  final String? missing; // 'IN' | 'OUT' | null

  @override
  Widget build(BuildContext context) {
    final side = (missing == 'IN' || missing == 'OUT') ? missing : null;
    final label = side != null
        ? 'Incomplete — missing $side'
        : 'Incomplete punch';
    return _pill(
      key: const ValueKey('incomplete-chip'),
      color: StatusColors.late,
      icon: Icons.report_problem_outlined,
      label: label,
    );
  }
}
