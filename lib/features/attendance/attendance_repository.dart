import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../models/attendance_day.dart';
import '../../models/weekly_hours.dart';

/// Fetches attendance history from the DRF API.
///
/// The list endpoint is paginated (PageNumberPagination, page size 25), so we
/// walk `next` pages to gather every day in the requested range.
class AttendanceRepository {
  AttendanceRepository(ApiClient client) : _dio = client.dio;

  final Dio _dio;

  /// All days from [start] to [end] inclusive, newest first (the backend
  /// already sorts descending).
  Future<List<AttendanceDay>> fetchRange(DateTime start, DateTime end) async {
    try {
      final days = <AttendanceDay>[];
      int page = 1;
      while (true) {
        final res = await _dio.get(
          ApiConfig.attendance,
          queryParameters: {
            'start': formatApiDate(start),
            'end': formatApiDate(end),
            'page': page,
          },
        );
        if (res.statusCode != 200 || res.data is! Map) {
          throw ApiException(res.statusCode, 'Could not load attendance.');
        }
        final data = res.data as Map;
        final results = (data['results'] as List? ?? const []);
        days.addAll(
          results.map(
            (e) => AttendanceDay.fromJson(Map<String, dynamic>.from(e)),
          ),
        );
        if (data['next'] == null) break;
        page += 1;
      }
      return days;
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Weekly worked-vs-required hours (part-time only; full-timers always get an
  /// empty list). [start]/[end] are both optional — the backend defaults to the
  /// last 4 weeks ending today. Not paginated (no `next`/`previous`), newest
  /// week first.
  Future<List<WeeklyHours>> fetchWeekly({DateTime? start, DateTime? end}) async {
    try {
      final res = await _dio.get(
        ApiConfig.attendanceWeekly,
        queryParameters: {
          if (start != null) 'start': formatApiDate(start),
          if (end != null) 'end': formatApiDate(end),
        },
      );
      if (res.statusCode != 200 || res.data is! Map) {
        throw ApiException(res.statusCode, 'Could not load weekly hours.');
      }
      final results = (res.data['results'] as List? ?? const []);
      return results
          .map((e) => WeeklyHours.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}

/// `YYYY-MM-DD`, the format the backend's `start`/`end` params expect.
String formatApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
