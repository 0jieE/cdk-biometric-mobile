import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/state_views.dart';
import '../../models/attendance_day.dart';
import '../../models/monthly_summary.dart';
import 'attendance_controller.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Column(
        children: [
          _RangeFilterBar(range: state.range, onTap: _pickRange),
          if (state.offline) OfflineBanner(lastSync: state.lastSync),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(attendanceControllerProvider.notifier).refresh(),
              child: _buildBody(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AttendanceState state) {
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
        _SummaryCard(summary: state.summary),
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

/// Header: date + day-status badge + optional OT badge.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(day.date);
    final label = date != null
        ? DateFormat('EEE, MMM d').format(date)
        : day.date;
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (day.hasOvertime) ...[
          OvertimeBadge(minutes: day.overtimeMinutes),
          const SizedBox(width: 6),
        ],
        DayStatusBadge(status: day.dayStatus),
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
              _TimeCol(label: 'IN', time: s?.timeIn),
              const SizedBox(width: 20),
              _TimeCol(label: 'OUT', time: s?.timeOut),
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

/// Part-time: single in/out row + incomplete warning when flagged.
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
                status: day.dayStatus == DayStatus.present
                    ? SessionStatus.present
                    : SessionStatus.absent,
              ),
          ],
        ),
        if (day.incomplete) ...[
          const SizedBox(height: 10),
          IncompleteChip(missing: day.missing),
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
        Text(_fmtTime(time), style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
