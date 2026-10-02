import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/features/attendance/attendance_controller.dart';
import 'package:biometric_mobile/features/attendance/attendance_screen.dart';
import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/monthly_summary.dart';

/// Fake controller that exposes a fixed state and never touches the network.
class _FakeAttendanceController extends AttendanceController {
  _FakeAttendanceController(this._seeded);
  final AttendanceState _seeded;

  @override
  AttendanceState build() => _seeded;

  @override
  Future<void> load({bool showSpinner = true}) async {}

  @override
  Future<void> refresh() async {}
}

Widget _wrap(AttendanceState seeded) => ProviderScope(
  overrides: [
    attendanceControllerProvider.overrideWith(
      () => _FakeAttendanceController(seeded),
    ),
  ],
  child: MaterialApp(home: AttendanceScreen(key: UniqueKey())),
);

void main() {
  testWidgets('full-time card renders AM/PM rows, late chip and OT badge', (
    tester,
  ) async {
    final seeded = AttendanceState(
      range: DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
      summary: const MonthlySummary(
        month: '2026-07',
        present: 8,
        late: 3,
        halfDay: 1,
        absent: 2,
        overtimeMinutes: 95, // 1h 35m
      ),
      days: [
        AttendanceDay(
          date: '2026-07-01',
          employeeType: EmployeeType.fullTime,
          dayStatus: DayStatus.late,
          am: AttendanceSession(
            timeIn: DateTime(2026, 7, 1, 8, 9),
            timeOut: DateTime(2026, 7, 1, 12, 0),
            status: SessionStatus.late,
            minutesLate: 4,
          ),
          pm: AttendanceSession(
            timeIn: DateTime(2026, 7, 1, 13, 14),
            timeOut: DateTime(2026, 7, 1, 17, 0),
            status: SessionStatus.late,
            minutesLate: 9,
          ),
          overtimeMinutes: 45,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(seeded));
    await tester.pump();

    // AM and PM labels both present.
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
    // Two late session chips with per-session minutes.
    expect(find.text('Late +4m'), findsOneWidget);
    expect(find.text('Late +9m'), findsOneWidget);
    // Day-status badge + OT badge.
    expect(find.byKey(const ValueKey('day-LATE')), findsOneWidget);
    expect(find.byKey(const ValueKey('ot-badge')), findsOneWidget);
    expect(find.text('OT 45m'), findsOneWidget);
    // Summary card shows all counts + total OT (1h 35m).
    expect(find.text('Summary'), findsOneWidget);
    // The selected range is shown once, on the filter bar above the summary.
    expect(find.text('Jul 1 – Jul 31, 2026'), findsOneWidget);
    expect(find.text('Half-day'), findsWidgets); // stat label + legend
    expect(find.text('1h 35m'), findsOneWidget);
    // Two labelled sections of the same tiles: day counts, then time totals.
    expect(find.text('DAYS'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    // Present = on time + late days (8 + 3); there is no separate Late day
    // count, lateness only appears as time. Lost time is late + undertime.
    expect(find.text('11'), findsOneWidget);
    expect(find.text('Total lost'), findsOneWidget);
    expect(find.text('Undertime'), findsOneWidget);
    // (Scoped to the summary card: the legend below also says "Overtime".)
    final card = find.byType(Card).first;
    for (final label in ['Present', 'Half-day', 'Absent', 'Late', 'Overtime']) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Total time lost'), findsNothing);
  });

  testWidgets('part-time incomplete card shows the missing-punch warning', (
    tester,
  ) async {
    final seeded = AttendanceState(
      range: DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
      summary: const MonthlySummary(
        month: '2026-07',
        present: 4,
        late: 0,
        halfDay: 0,
        absent: 1,
        overtimeMinutes: 0,
      ),
      days: [
        AttendanceDay(
          date: '2026-07-02',
          employeeType: EmployeeType.partTime,
          dayStatus: DayStatus.absent,
          ptIn: DateTime(2026, 7, 2, 9, 4),
          ptOut: null,
          incomplete: true,
          missing: 'OUT',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(seeded));
    await tester.pump();

    expect(find.byKey(const ValueKey('incomplete-chip')), findsOneWidget);
    expect(find.text('Incomplete — missing OUT'), findsOneWidget);
    // Still reads as Absent for the day.
    expect(find.byKey(const ValueKey('day-ABSENT')), findsOneWidget);
    // Missing OUT punch renders as an em dash.
    expect(find.text('—'), findsWidgets);
  });
}
