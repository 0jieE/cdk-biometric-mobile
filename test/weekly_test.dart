import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:biometric_mobile/core/config/api_config.dart';
import 'package:biometric_mobile/core/network/api_client.dart';
import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/cache_store.dart';
import 'package:biometric_mobile/features/attendance/attendance_controller.dart';
import 'package:biometric_mobile/features/attendance/attendance_repository.dart';
import 'package:biometric_mobile/features/attendance/attendance_screen.dart'
    show WeeklyProgressCard, describeShortfall, formatWeek, formatWeekDays;
import 'package:biometric_mobile/features/attendance/weekly_controller.dart';
import 'package:biometric_mobile/models/attendance_day.dart';
import 'package:biometric_mobile/models/weekly_hours.dart';

import 'helpers.dart';

const _root = 'http://test.local/api/v1';

/// Shape copied from the live API (`GET /attendance/weekly/`, emp-1007).
const _liveResults = [
  {
    'week_start': '2026-09-14',
    'week_end': '2026-09-20',
    'worked_minutes': 2175,
    'required_minutes': 180,
    'remaining_minutes': 0,
    'days_worked': 4,
    'required_days': 2,
    'remaining_days': 0,
    'status': 'MET',
  },
  {
    'week_start': '2026-09-07',
    'week_end': '2026-09-13',
    'worked_minutes': 90,
    'required_minutes': 180,
    'remaining_minutes': 90,
    'days_worked': 1,
    'required_days': 2,
    'remaining_days': 1,
    'status': 'SHORT',
  },
];

/// Backend example: enough hours, but on only one day → still SHORT.
const _enoughHoursTooFewDays = {
  'week_start': '2026-07-06',
  'week_end': '2026-07-12',
  'worked_minutes': 660,
  'required_minutes': 600,
  'remaining_minutes': 0,
  'days_worked': 1,
  'required_days': 2,
  'remaining_days': 1,
  'status': 'SHORT',
};

void main() {
  group('WeeklyHours parsing', () {
    test('parses the live shape and computes fraction', () {
      final w = WeeklyHours.fromJson(_liveResults[0]);
      expect(w.weekStart, '2026-09-14');
      expect(w.weekEnd, '2026-09-20');
      expect(w.workedMinutes, 2175);
      expect(w.requiredMinutes, 180);
      expect(w.status, WeekStatus.met);
      // Worked well over required; fraction clamps at 1.0, not >1.
      expect(w.fraction, 1.0);
    });

    test('fraction is proportional and never negative/over 1', () {
      final w = WeeklyHours.fromJson(_liveResults[1]);
      expect(w.fraction, closeTo(90 / 180, 0.0001));
      final zero = WeeklyHours.fromJson({
        ..._liveResults[1],
        'worked_minutes': 0,
      });
      expect(zero.fraction, 0.0);
    });

    test('round-trips through toJson (offline cache)', () {
      final w = WeeklyHours.fromJson(_liveResults[1]);
      final again = WeeklyHours.fromJson(w.toJson());
      expect(again.weekStart, w.weekStart);
      expect(again.status, w.status);
      expect(again.workedMinutes, w.workedMinutes);
    });

    test('an unrecognized status string falls back to unknown, not a crash',
        () {
      final w = WeeklyHours.fromJson({..._liveResults[0], 'status': 'NEW'});
      expect(w.status, WeekStatus.unknown);
    });

    test('parses required_days / remaining_days and round-trips them', () {
      final w = WeeklyHours.fromJson(_enoughHoursTooFewDays);
      expect((w.requiredDays, w.remainingDays), (2, 1));
      final again = WeeklyHours.fromJson(w.toJson());
      expect((again.requiredDays, again.remainingDays), (2, 1));
    });

    test('an older cached entry without the day fields defaults them to 0', () {
      final old = Map<String, dynamic>.of(_liveResults[0])
        ..remove('required_days')
        ..remove('remaining_days');
      final w = WeeklyHours.fromJson(old);
      expect((w.requiredDays, w.remainingDays), (0, 0));
      expect(formatWeekDays(w), '4 days');
    });
  });

  group('Shortfall text', () {
    test('enough hours on too few days is SHORT by days only (status is '
        'trusted, not inferred from hours)', () {
      final w = WeeklyHours.fromJson(_enoughHoursTooFewDays);
      expect(w.status, WeekStatus.short);
      expect(describeShortfall(w), '1 day');
      expect(formatWeekDays(w), '1 / 2 days');
    });

    test('short on both hours and days joins them with "&"', () {
      final w = WeeklyHours.fromJson({
        ..._enoughHoursTooFewDays,
        'remaining_minutes': 150,
        'remaining_days': 2,
        'days_worked': 0,
      });
      expect(describeShortfall(w), '2h 30m & 2 days');
    });

    test('short on hours only', () {
      final w = WeeklyHours.fromJson({
        ..._enoughHoursTooFewDays,
        'remaining_minutes': 150,
        'remaining_days': 0,
        'days_worked': 2,
      });
      expect(describeShortfall(w), '2h 30m');
    });

    test('a MET week has no shortfall', () {
      expect(describeShortfall(WeeklyHours.fromJson(_liveResults[0])), isNull);
    });
  });

  group('AttendanceRepository.fetchWeekly', () {
    test('GET /attendance/weekly/ with optional start/end, parses `results`',
        () async {
      RequestOptions? seen;
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter((opts) {
          seen = opts;
          return const FakeResponse(200, {'results': _liveResults});
        });
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
        dio: dio,
      );
      final repo = AttendanceRepository(client);

      final weeks = await repo.fetchWeekly(
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 20),
      );

      expect(seen!.path, ApiConfig.attendanceWeekly);
      expect(seen!.queryParameters, {
        'start': '2026-09-07',
        'end': '2026-09-20',
      });
      expect(weeks.length, 2);
      expect(weeks.first.status, WeekStatus.met);
    });

    test('omits start/end entirely when not given (backend applies its own '
        'default window)', () async {
      RequestOptions? seen;
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter((opts) {
          seen = opts;
          return const FakeResponse(200, {'results': []});
        });
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
        dio: dio,
      );

      await AttendanceRepository(client).fetchWeekly();

      expect(seen!.queryParameters, isEmpty);
    });

    test('a full-timer gets an empty list (no error)', () async {
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter(
          (_) => const FakeResponse(200, {'results': []}),
        );
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
        dio: dio,
      );

      expect(await AttendanceRepository(client).fetchWeekly(), isEmpty);
    });

    test('start after end surfaces the backend\'s 400 as ApiException',
        () async {
      final dio = Dio(BaseOptions(baseUrl: _root))
        ..httpClientAdapter = FakeHttpAdapter(
          (_) => const FakeResponse(400, {
            'detail': 'start must be on or before end.',
          }),
        );
      final client = ApiClient(
        apiRoot: _root,
        tokenStore: InMemoryTokenStore(),
        onForceLogout: () async {},
        dio: dio,
      );

      await expectLater(
        AttendanceRepository(client).fetchWeekly(
          start: DateTime(2026, 11, 2),
          end: DateTime(2026, 10, 1),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'start must be on or before end.',
          ),
        ),
      );
    });
  });

  group('WeeklyController', () {
    late Database db;
    late CacheStore cache;

    setUp(() async {
      db = await openTestDatabase();
      cache = CacheStore(db);
    });

    tearDown(() => db.close());

    test('load() fetches, caches, and exposes current/past', () async {
      final weeks = _liveResults.map(WeeklyHours.fromJson).toList();
      final container = ProviderContainer(
        overrides: [
          cacheStoreProvider.overrideWithValue(cache),
          attendanceRepositoryProvider.overrideWithValue(_FixedWeeklyRepo(weeks)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(weeklyControllerProvider.notifier).load();
      final state = container.read(weeklyControllerProvider);

      expect(state.offline, isFalse);
      expect(state.current?.status, WeekStatus.met);
      expect(state.past.length, 1);
      expect(state.past.single.status, WeekStatus.short);
      expect((await cache.readWeekly())?.length, 2);
    });

    test('a network error falls back to the cache and flags offline',
        () async {
      final weeks = _liveResults.map(WeeklyHours.fromJson).toList();
      await cache.saveWeekly(weeks);

      final container = ProviderContainer(
        overrides: [
          cacheStoreProvider.overrideWithValue(cache),
          attendanceRepositoryProvider.overrideWithValue(_OfflineWeeklyRepo()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(weeklyControllerProvider.notifier).load();
      final state = container.read(weeklyControllerProvider);

      expect(state.offline, isTrue);
      expect(state.error, isNull);
      expect(state.weeks.length, 2);
    });

    test('a network error with nothing cached surfaces an error state',
        () async {
      final container = ProviderContainer(
        overrides: [
          cacheStoreProvider.overrideWithValue(cache),
          attendanceRepositoryProvider.overrideWithValue(_OfflineWeeklyRepo()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(weeklyControllerProvider.notifier).load();
      final state = container.read(weeklyControllerProvider);

      expect(state.offline, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.error, isNotNull);
    });
  });

  group('WeeklyProgressCard widget', () {
    testWidgets('shows the current week\'s progress + past weeks list', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final weeks = _liveResults.map(WeeklyHours.fromJson).toList();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyControllerProvider.overrideWith(
              () => _SeededWeeklyController(WeeklyState(weeks: weeks)),
            ),
          ],
          // Scrollable host, same as the real app (the card lives in a
          // ListView) — the test shouldn't depend on guessing its exact height.
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: WeeklyProgressCard()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('This week'), findsOneWidget);
      expect(find.text(formatWeek(weeks[0])), findsOneWidget);
      // Worked (2175m = 36h 15m) and required (180m = 3h) render formatted,
      // not as raw minute counts.
      expect(find.text('36h 15m'), findsOneWidget);
      expect(find.text(' / 3h'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('week-MET')), findsOneWidget);
      // _SectionLabel uppercases (same convention as the Days/Time summary).
      expect(find.text('PAST WEEKS'), findsOneWidget);
      expect(find.text(formatWeek(weeks[1])), findsOneWidget);
      expect(find.byKey(const ValueKey('week-SHORT')), findsOneWidget);
      expect(find.text('Short by 1h 30m & 1 day'), findsOneWidget);
    });

    testWidgets('an in-progress week says what is still to go, hours + days', (
      tester,
    ) async {
      final week = WeeklyHours.fromJson({
        ..._enoughHoursTooFewDays,
        'status': 'IN_PROGRESS',
        'remaining_minutes': 150,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyControllerProvider.overrideWith(
              () => _SeededWeeklyController(WeeklyState(weeks: [week])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: WeeklyProgressCard()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('1 / 2 days worked · 2h 30m & 1 day to go'),
        findsOneWidget,
      );
    });

    testWidgets('an empty result shows a friendly message, not a blank card',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weeklyControllerProvider.overrideWith(
              () => _SeededWeeklyController(const WeeklyState()),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: WeeklyProgressCard())),
        ),
      );
      await tester.pump();

      expect(find.textContaining('No weekly hours yet'), findsOneWidget);
    });
  });
}

class _FixedWeeklyRepo implements AttendanceRepository {
  _FixedWeeklyRepo(this.weeks);
  final List<WeeklyHours> weeks;

  @override
  Future<List<WeeklyHours>> fetchWeekly({DateTime? start, DateTime? end}) async =>
      weeks;

  @override
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async =>
      [];
}

class _OfflineWeeklyRepo implements AttendanceRepository {
  @override
  Future<List<WeeklyHours>> fetchWeekly({DateTime? start, DateTime? end}) async =>
      throw const NetworkUnavailable();

  @override
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async =>
      [];
}

/// Fake controller that exposes a fixed state and never touches the network.
class _SeededWeeklyController extends WeeklyController {
  _SeededWeeklyController(this._seeded);
  final WeeklyState _seeded;

  @override
  WeeklyState build() => _seeded;

  @override
  Future<void> load({bool showSpinner = true}) async {}

  @override
  Future<void> refresh() async {}
}
