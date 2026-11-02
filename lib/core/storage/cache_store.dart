import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../models/app_notification.dart';
import '../../models/attendance_day.dart';
import '../../models/employee.dart';
import '../../models/weekly_hours.dart';

/// Offline cache backed by Hive. Values are stored as JSON strings (manual
/// serialization) so no generated type adapters are required.
///
/// This is the local store behind the paper's "offline data synchronization"
/// requirement: every successful network fetch writes here, and network
/// failures read back from here.
class CacheStore {
  CacheStore(this._box);

  final Box _box;

  static const String boxName = 'biometric_cache';

  // Keys
  static const _kProfile = 'profile';
  static const _kAttendancePrefix = 'attendance:'; // + start..end (YYYY-MM-DD)
  static const _kNotifications = 'notifications';
  static const _kWeekly = 'weekly'; // part-time weekly hours (single slot)
  static const _kLastSyncPrefix = 'lastsync:'; // + logical key

  /// Open (or create) the cache box. Call once at startup.
  static Future<CacheStore> open() async {
    final box = await Hive.openBox(boxName);
    return CacheStore(box);
  }

  // ---- Profile ------------------------------------------------------------

  Future<void> saveProfile(Employee employee) async {
    await _box.put(_kProfile, jsonEncode(employee.toJson()));
    await _touch(_kProfile);
  }

  Employee? readProfile() {
    final raw = _box.get(_kProfile) as String?;
    if (raw == null) return null;
    try {
      return Employee.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // stale/incompatible cache — fail soft
    }
  }

  // ---- Attendance list (keyed by date range) ------------------------------

  Future<void> saveAttendance(String rangeKey, List<AttendanceDay> days) async {
    final encoded = jsonEncode(days.map((d) => d.toJson()).toList());
    await _box.put('$_kAttendancePrefix$rangeKey', encoded);
    await _touch('$_kAttendancePrefix$rangeKey');
  }

  List<AttendanceDay>? readAttendance(String rangeKey) {
    final raw = _box.get('$_kAttendancePrefix$rangeKey') as String?;
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AttendanceDay.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null; // stale/incompatible cache — fail soft
    }
  }

  // ---- Notifications ------------------------------------------------------

  Future<void> saveNotifications(List<AppNotification> notes) async {
    final encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
    await _box.put(_kNotifications, encoded);
    await _touch(_kNotifications);
  }

  List<AppNotification>? readNotifications() {
    final raw = _box.get(_kNotifications) as String?;
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ---- Weekly hours (part-time; single slot — "last 4 weeks ending today")

  Future<void> saveWeekly(List<WeeklyHours> weeks) async {
    final encoded = jsonEncode(weeks.map((w) => w.toJson()).toList());
    await _box.put(_kWeekly, encoded);
    await _touch(_kWeekly);
  }

  List<WeeklyHours>? readWeekly() {
    final raw = _box.get(_kWeekly) as String?;
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WeeklyHours.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null; // stale/incompatible cache — fail soft
    }
  }

  DateTime? lastSyncWeekly() => lastSyncFor(_kWeekly);

  // ---- Last-sync timestamps ----------------------------------------------

  Future<void> _touch(String key) =>
      _box.put('$_kLastSyncPrefix$key', DateTime.now().toIso8601String());

  DateTime? lastSyncFor(String key) {
    final raw = _box.get('$_kLastSyncPrefix$key') as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  DateTime? lastSyncAttendance(String rangeKey) =>
      lastSyncFor('$_kAttendancePrefix$rangeKey');

  DateTime? lastSyncNotifications() => lastSyncFor(_kNotifications);

  /// Wipe all cached data (used on logout).
  Future<void> clear() => _box.clear();
}
