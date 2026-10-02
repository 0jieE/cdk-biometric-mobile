import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../models/attendance_day.dart';

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
}

/// `YYYY-MM-DD`, the format the backend's `start`/`end` params expect.
String formatApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
