import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/theme/theme_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeNotifier', () {
    test('initial value is ThemeMode.system', () {
      final sut = ThemeNotifier();
      expect(sut.value, ThemeMode.system);
    });

    test('load reads light from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      final sut = ThemeNotifier();
      await sut.load();
      expect(sut.value, ThemeMode.light);
    });

    test('load reads dark from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final sut = ThemeNotifier();
      await sut.load();
      expect(sut.value, ThemeMode.dark);
    });

    test('load defaults to system for unknown value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'invalid'});
      final sut = ThemeNotifier();
      await sut.load();
      expect(sut.value, ThemeMode.system);
    });

    test('load defaults to system when no value stored', () async {
      SharedPreferences.setMockInitialValues({});
      final sut = ThemeNotifier();
      await sut.load();
      expect(sut.value, ThemeMode.system);
    });

    test('setMode persists value', () async {
      SharedPreferences.setMockInitialValues({});
      final sut = ThemeNotifier();
      await sut.setMode(ThemeMode.dark);

      expect(sut.value, ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('setMode notifies listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final sut = ThemeNotifier();
      ThemeMode? notified;
      sut.addListener(() => notified = sut.value);

      await sut.setMode(ThemeMode.light);
      expect(notified, ThemeMode.light);
    });
  });
}
