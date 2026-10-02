import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/core/providers.dart';
import 'package:biometric_mobile/core/storage/settings_store.dart';
import 'package:biometric_mobile/core/theme/app_theme.dart';
import 'package:biometric_mobile/core/theme/theme_controller.dart';

class _FakeSettingsStore implements SettingsStore {
  String? accent;
  String? themeMode;

  @override
  String? readAccent() => accent;
  @override
  Future<void> saveAccent(String v) async => accent = v;
  @override
  String? readThemeMode() => themeMode;
  @override
  Future<void> saveThemeMode(String v) async => themeMode = v;
}

void main() {
  ProviderContainer containerWith(_FakeSettingsStore store) {
    final c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to Purple + Dark when nothing is stored', () {
    final c = containerWith(_FakeSettingsStore());
    final s = c.read(themeControllerProvider);
    expect(s.accent, AppAccent.purple);
    expect(s.mode, ThemeMode.dark);
  });

  test('restores a persisted accent + light mode', () {
    final store = _FakeSettingsStore()
      ..accent = 'teal'
      ..themeMode = 'light';
    final c = containerWith(store);
    final s = c.read(themeControllerProvider);
    expect(s.accent, AppAccent.teal);
    expect(s.mode, ThemeMode.light);
  });

  test('setAccent updates state and persists', () async {
    final store = _FakeSettingsStore();
    final c = containerWith(store);

    await c.read(themeControllerProvider.notifier).setAccent(AppAccent.rose);

    expect(c.read(themeControllerProvider).accent, AppAccent.rose);
    expect(store.accent, 'rose');
  });

  test('toggleDark persists the light/dark choice', () async {
    final store = _FakeSettingsStore();
    final c = containerWith(store);

    await c.read(themeControllerProvider.notifier).toggleDark(false);
    expect(c.read(themeControllerProvider).mode, ThemeMode.light);
    expect(store.themeMode, 'light');

    await c.read(themeControllerProvider.notifier).toggleDark(true);
    expect(store.themeMode, 'dark');
  });
}
