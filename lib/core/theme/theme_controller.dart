import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'app_theme.dart';

/// Current theme preferences: brand [accent] + [mode] (light/dark).
@immutable
class ThemeSettings {
  final AppAccent accent;
  final ThemeMode mode;

  const ThemeSettings({required this.accent, required this.mode});

  ThemeSettings copyWith({AppAccent? accent, ThemeMode? mode}) =>
      ThemeSettings(accent: accent ?? this.accent, mode: mode ?? this.mode);
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);

/// Holds + persists the accent and light/dark preference. Default = Purple,
/// Dark (the app looks great dark). Changes apply live and survive restarts.
class ThemeController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    final store = ref.read(settingsStoreProvider);
    final accent = accentFromKey(store.readAccent());
    final mode = _modeFromKey(store.readThemeMode());
    return ThemeSettings(accent: accent, mode: mode);
  }

  Future<void> setAccent(AppAccent accent) async {
    await ref.read(settingsStoreProvider).saveAccent(accent.key);
    state = state.copyWith(accent: accent);
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(settingsStoreProvider).saveThemeMode(_modeToKey(mode));
    state = state.copyWith(mode: mode);
  }

  Future<void> toggleDark(bool dark) =>
      setMode(dark ? ThemeMode.dark : ThemeMode.light);

  static ThemeMode _modeFromKey(String? key) => switch (key) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    // Default is dark — the app was designed to look great dark.
    _ => ThemeMode.dark,
  };

  static String _modeToKey(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
    ThemeMode.dark => 'dark',
  };
}
