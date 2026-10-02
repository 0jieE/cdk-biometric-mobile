import 'package:hive_flutter/hive_flutter.dart';

/// Abstraction over app-settings persistence so it can be faked in tests.
abstract class SettingsStore {
  /// Theme preferences (Phase 11). Accent key (e.g. 'purple') and theme mode
  /// ('light' | 'dark' | 'system'). Null when never set.
  String? readAccent();
  Future<void> saveAccent(String accentKey);
  String? readThemeMode();
  Future<void> saveThemeMode(String mode);
}

/// Hive-backed settings. Uses its own box, separate from the attendance/profile
/// cache, so theme preferences survive logout (logout only clears the cache box).
class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore(this._box);

  final Box _box;

  static const String boxName = 'app_settings';
  static const String _kAccent = 'theme_accent';
  static const String _kThemeMode = 'theme_mode';

  static Future<HiveSettingsStore> open() async {
    final box = await Hive.openBox(boxName);
    return HiveSettingsStore(box);
  }

  @override
  String? readAccent() => _box.get(_kAccent) as String?;

  @override
  Future<void> saveAccent(String accentKey) => _box.put(_kAccent, accentKey);

  @override
  String? readThemeMode() => _box.get(_kThemeMode) as String?;

  @override
  Future<void> saveThemeMode(String mode) => _box.put(_kThemeMode, mode);
}
