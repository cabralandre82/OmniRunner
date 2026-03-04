import 'package:flutter/material.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app's [ThemeMode] and persists the choice via SharedPreferences.
///
/// Three modes: system (default), light, dark.
class ThemeNotifier extends ValueNotifier<ThemeMode> {

  ThemeNotifier() : super(ThemeMode.system);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(PreferencesKeys.themeMode);
    if (stored == 'light') {
      value = ThemeMode.light;
    } else if (stored == 'dark') {
      value = ThemeMode.dark;
    } else {
      value = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferencesKeys.themeMode, mode.name);
  }
}
