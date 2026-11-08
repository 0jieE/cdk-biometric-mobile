import 'package:sqflite/sqflite.dart';

/// Abstraction over app-settings persistence so it can be faked in tests.
abstract class SettingsStore {
  /// Theme preferences (Phase 11). Accent key (e.g. 'purple') and theme mode
  /// ('light' | 'dark' | 'system'). Null when never set.
  String? readAccent();
  Future<void> saveAccent(String accentKey);
  String? readThemeMode();
  Future<void> saveThemeMode(String mode);
}

/// Settings in the `app_setting` table, separate from the cached API data, so
/// theme preferences survive logout (logout only clears the cache tables).
///
/// All rows are loaded once in [open], so reads are synchronous — the theme is
/// needed to draw the very first frame.
class SqliteSettingsStore implements SettingsStore {
  SqliteSettingsStore._(this._db, this._values);

  final Database _db;
  final Map<String, String> _values;

  static const String _kAccent = 'theme_accent';
  static const String _kThemeMode = 'theme_mode';

  static Future<SqliteSettingsStore> open(Database db) async {
    final rows = await db.query('app_setting');
    return SqliteSettingsStore._(db, {
      for (final r in rows) r['key'] as String: r['value'] as String,
    });
  }

  Future<void> _save(String key, String value) async {
    _values[key] = value;
    await _db.insert(
      'app_setting',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  String? readAccent() => _values[_kAccent];

  @override
  Future<void> saveAccent(String accentKey) => _save(_kAccent, accentKey);

  @override
  String? readThemeMode() => _values[_kThemeMode];

  @override
  Future<void> saveThemeMode(String mode) => _save(_kThemeMode, mode);
}
