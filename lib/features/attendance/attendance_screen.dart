import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/state_views.dart';
import '../../models/attendance_day.dart';
import '../../models/monthly_summary.dart';
import '../../models/weekly_hours.dart';
import '../auth/auth_controller.dart';
import 'attendance_controller.dart';
import 'weekly_controller.dart';
import 'widgets/attendance_chips.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    // First load once the widget tree is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(attendanceControllerProvider.notifier).load();
    });
  }

  Future<void> _pickRange() async {
    final current = ref.read(attendanceControllerProvider).range;
    final today = toManila(DateTime.now());
    final lastDay = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(lastDay.year - 3, 1, 1),
      lastDate: lastDay,
      initialDateRange: current,
      helpText: 'Select a date range',
      saveText: 'Apply',
    );
    if (picked != null) {
      await ref.read(attendanceControllerProvider.notifier).selectRange(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceControllerProvider);
    final employee = ref.watch(authControllerProvider).employee;
    final isFulltime = employee?.isFulltime ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Column(
        children: [
          _RangeFilterBar(range: state.range, onTap: _pickRange),
          if (state.offline) OfflineBanner(lastSync: state.lastSync),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.read(attendanceControllerProvider.notifier).refresh(),
                if (!isFulltime)
                  ref.read(weeklyControllerProvider.notifier).refresh(),
              ]),
              child: _buildBody(state, isFulltime: isFulltime),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AttendanceState state, {required bool isFulltime}) {
    if (state.loading && state.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.isEmpty) {
      return ListView(
        // ListView so pull-to-refresh works even in the error state.
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          MessageView(
            icon: Icons.wifi_off,
            title: 'Could not load attendance',
            subtitle: state.error,
            onRetry: () =>
                ref.read(attendanceControllerProvider.notifier).load(),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Full-timers are judged per day/session: Days + Time card. Part-timers
        // are judged on weekly hours (see WeeklyProgressCard) — a Days/Time card
        // would be all zeros for them now that there's no daily pass/fail.
        if (isFulltime)
          _SummaryCard(summary: state.summary)
        else
          const WeeklyProgressCard(),
        const SizedBox(height: 20),
        Text('Daily records', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const _Legend(),
        const SizedBox(height: 12),
        if (state.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: MessageView(
              icon: Icons.event_busy,
              title: 'No attendance records',
              subtitle: 'There are no records for this date range.',
            ),
          )
        else
          ...state.days.map((d) => _AttendanceTile(day: d)),
      ],
    );
  }
}

/// Tappable bar showing the selected date range; opens the range picker.
class _RangeFilterBar extends StatelessWidget {
  const _RangeFilterBar({required this.range, required this.onTap});
  final DateTimeRange range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.date_range, size: 20),
        label: Row(
          children: [
            Expanded(child: Text(formatRange(range))),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

/// "Sep 1 – Sep 21, 2026", "Sep 21, 2026" for one day, or with both years when
/// the range spans two.
String formatRange(DateTimeRange r) {
  final start = r.start, end = r.end;
  if (start == end) return DateFormat('MMM d, y').format(start);
  if (start.year == end.year) {
    return '${DateFormat('MMM d').format(start)} – '
        '${DateFormat('MMM d, y').format(end)}';
  }
  return '${DateFormat('MMM d, y').format(start)} – '
      '${DateFormat('MMM d, y').format(end)}';
}

String _fmtTime(DateTime? t) =>
    t != null ? DateFormat('h:mm a').format(toManila(t)) : '—';

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const _SectionLabel('Days'),
            const SizedBox(height: 8),
            Row(
              children: [
                _SummaryStat(
                  label: 'Present',
                  value: '${summary.daysPresent}',
                  color: StatusColors.present,
                  icon: Icons.check_circle_outline,
                ),
                _SummaryStat(
                  label: 'Half-day',
                  value: '${summary.halfDay}',
                  color: StatusColors.halfDay,
                  icon: Icons.hourglass_bottom,
                ),
                _SummaryStat(
                  label: 'Absent',
                  value: '${summary.absent}',
                  color: StatusColors.absent,
                  icon: Icons.cancel_outlined,
                ),
              ],
            ),
            const Divider(height: 28),
            const _SectionLabel('Time'),
            const SizedBox(height: 8),
            // Row 1: the three components (same 3-tile layout as "Days", for
            // visual uniformity). Row 2: the two totals derived from them.
            Row(
              children: [
                _SummaryStat(
                  label: 'Late',
                  value: formatMinutes(summary.lateMinutes),
                  color: StatusColors.late,
                  icon: Icons.timer_outlined,
                ),
                _SummaryStat(
                  label: 'Undertime',
                  value: formatMinutes(summary.undertimeMinutes),
                  color: StatusColors.halfDay,
                  icon: Icons.exit_to_app,
                ),
                _SummaryStat(
                  label: 'Absence',
                  value: formatMinutes(summary.absentMinutes),
                  color: StatusColors.absent,
                  icon: Icons.event_busy_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _SummaryStat(
                  label: 'Total lost',
                  value: formatMinutes(summary.lostMinutes),
                  color: StatusColors.absent,
                  icon: Icons.timer_off_outlined,
                ),
                _SummaryStat(
                  label: 'Overtime',
                  value: formatMinutes(summary.overtimeMinutes),
                  color: StatusColors.overtime,
                  icon: Icons.more_time,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small caps-style heading for a group of tiles in the summary card.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.hintColor,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Color for a week's big "worked" number, matching [WeekStatusBadge].
Color _weekColor(WeekStatus s) => switch (s) {
  WeekStatus.met => StatusColors.present,
  WeekStatus.inProgress => StatusColors.pending,
  WeekStatus.short => StatusColors.absent,
  WeekStatus.unknown => StatusColors.unknown,
};

/// "Sep 28 – Oct 4, 2026" for a week's raw YYYY-MM-DD start/end strings.
String formatWeek(WeeklyHours w) {
  final start = DateTime.tryParse(w.weekStart);
  final end = DateTime.tryParse(w.weekEnd);
  if (start == null || end == null) return '${w.weekStart} – ${w.weekEnd}';
  return start.year == end.year
      ? '${DateFormat('MMM d').format(start)} – '
            '${DateFormat('MMM d, y').format(end)}'
      : '${DateFormat('MMM d, y').format(start)} – '
            '${DateFormat('MMM d, y').format(end)}';
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// "1 / 2 days" (or "3 days" when the backend didn't send `required_days`).
String formatWeekDays(WeeklyHours w) => w.requiredDays > 0
    ? '${w.daysWorked} / ${_days(w.requiredDays)}'
    : _days(w.daysWorked);

/// What a not-yet-met week is missing: "2h 30m", "1 day" or "2h 30m & 1 day".
/// Null for a MET week or when nothing is reported missing. Note
/// remaining_minutes can be 0 on a week that's still SHORT (enough hours, too
/// few days).
String? describeShortfall(WeeklyHours w) {
  if (w.status == WeekStatus.met) return null;
  final parts = [
    if (w.remainingMinutes > 0) formatMinutes(w.remainingMinutes),
    if (w.remainingDays > 0) _days(w.remainingDays),
  ];
  return parts.isEmpty ? null : parts.join(' & ');
}

/// Part-time weekly hours: "This week" progress (worked vs. required, with a
/// progress bar) plus a short list of past weeks. Loads itself on mount;
/// `refresh` is called alongside the attendance list's own pull-to-refresh
/// (see [_AttendanceScreenState.build]).
class WeeklyProgressCard extends ConsumerStatefulWidget {
  const WeeklyProgressCard({super.key});

  @override
  ConsumerState<WeeklyProgressCard> createState() =>
      _WeeklyProgressCardState();
}

class _WeeklyProgressCardState extends ConsumerState<WeeklyProgressCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weeklyControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weeklyControllerProvider);
    final theme = Theme.of(context);

    if (state.loading && state.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (state.error != null && state.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This week', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(state.error!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    ref.read(weeklyControllerProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final current = state.current;
    if (current == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No weekly hours yet — they will appear once your attendance '
            'starts being tracked.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final color = _weekColor(current.status);
    final past = state.past;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('This week', style: theme.textTheme.titleMedium),
                if (state.offline) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.cloud_off_outlined, size: 16, color: theme.hintColor),
                ],
                const Spacer(),
                WeekStatusBadge(status: current.status),
              ],
            ),
            Text(
              formatWeek(current),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatMinutes(current.workedMinutes),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  ' / ${formatMinutes(current.requiredMinutes)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: current.fraction,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              key: const ValueKey('week-current-detail'),
              [
                '${formatWeekDays(current)} worked',
                if (describeShortfall(current) case final missing?)
                  current.status == WeekStatus.short
                      ? 'Short by $missing'
                      : '$missing to go',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            if (past.isNotEmpty) ...[
              const Divider(height: 28),
              const _SectionLabel('Past weeks'),
              const SizedBox(height: 8),
              ...past.map((w) => _PastWeekRow(week: w)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PastWeekRow extends StatelessWidget {
  const _PastWeekRow({required this.week});
  final WeeklyHours week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = describeShortfall(week);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatWeek(week), style: theme.textTheme.bodyMedium),
                Text(
                  '${formatMinutes(week.workedMinutes)} / '
                  '${formatMinutes(week.requiredMinutes)} · '
                  '${formatWeekDays(week)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
                if (week.status == WeekStatus.short && missing != null)
                  Text(
                    'Short by $missing',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: StatusColors.absent,
                    ),
                  ),
              ],
            ),
          ),
          WeekStatusBadge(status: week.status),
        ],
      ),
    );
  }
}

/// Subtle color key for the status chips.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        dot(StatusColors.present, 'On time'),
        dot(StatusColors.late, 'Late'),
        dot(StatusColors.halfDay, 'Half-day'),
        dot(StatusColors.absent, 'Absent / Missing'),
        dot(StatusColors.overtime, 'Overtime'),
      ],
    );
  }
}

/// Routes to the correct card for the employee type.
class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DayHeader(day: day),
            const SizedBox(height: 10),
            if (day.isFulltime)
              _FulltimeBody(day: day)
            else
              _ParttimeBody(day: day),
          ],
        ),
      ),
    );
  }
}

/// Header: date + day-status badge + optional OT badge, + an optional
/// special-event note (e.g. a credited "Foundation Day (AM required)").
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(day.date);
    final label = date != null
        ? DateFormat('EEE, MMM d').format(date)
        : day.date;
    final event = day.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            // Wrap (not a fixed Row) so the OT + status badges drop to a
            // second line on a narrow phone instead of overflowing — both
            // can appear together (e.g. a LATE day with overtime).
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (day.hasOvertime) OvertimeBadge(minutes: day.overtimeMinutes),
                  DayStatusBadge(status: day.dayStatus),
                ],
              ),
            ),
          ],
        ),
        if (event != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.celebration_outlined,
                  size: 14, color: Theme.of(context).hintColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  event,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Full-time: AM and PM rows.
class _FulltimeBody extends StatelessWidget {
  const _FulltimeBody({required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SessionRow(label: 'AM', session: day.am),
        const SizedBox(height: 8),
        _SessionRow(label: 'PM', session: day.pm),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.label, required this.session});
  final String label;
  final AttendanceSession? session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _TimeCol(label: 'IN', time: s?.timeIn)),
              const SizedBox(width: 12),
              Expanded(child: _TimeCol(label: 'OUT', time: s?.timeOut)),
            ],
          ),
        ),
        if (s != null)
          SessionChip(status: s.status, minutesLate: s.minutesLate)
        else
          const SessionChip(status: SessionStatus.unknown),
      ],
    );
  }
}

/// Part-time: single in/out row, hours worked, + incomplete warning when
/// flagged. A part-timer is judged on weekly hours (see [WeeklyProgressCard]),
/// not a daily window, so there is no "Absent" chip here any more — only
/// Present / In progress (today) / Incomplete.
class _ParttimeBody extends StatelessWidget {
  const _ParttimeBody({required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _TimeCol(label: 'IN', time: day.ptIn),
                  const SizedBox(width: 20),
                  _TimeCol(label: 'OUT', time: day.ptOut),
                ],
              ),
            ),
            if (!day.incomplete)
              SessionChip(
                status: day.dayStatus == DayStatus.pending
                    ? SessionStatus.pending
                    : SessionStatus.present,
              ),
          ],
        ),
        if (day.incomplete) ...[
          const SizedBox(height: 10),
          IncompleteChip(missing: day.missing),
        ] else if (day.workedMinutes > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Worked ${formatMinutes(day.workedMinutes)}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: StatusColors.present),
          ),
        ],
      ],
    );
  }
}

class _TimeCol extends StatelessWidget {
  const _TimeCol({required this.label, required this.time});
  final String label;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
        ),
        Text(
          _fmtTime(time),
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
