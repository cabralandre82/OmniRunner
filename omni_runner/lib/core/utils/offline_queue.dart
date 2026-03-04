import 'dart:convert';

import 'package:omni_runner/core/storage/preferences_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineQueue {
  static Future<void> enqueue(Map<String, dynamic> task) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(PreferencesKeys.offlineQueue) ?? [];
    queue.add(jsonEncode(task));
    await prefs.setStringList(PreferencesKeys.offlineQueue, queue);
  }

  static Future<List<Map<String, dynamic>>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(PreferencesKeys.offlineQueue) ?? [];
    return queue.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PreferencesKeys.offlineQueue);
  }

  static Future<void> saveRemaining(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(PreferencesKeys.offlineQueue);
    } else {
      await prefs.setStringList(
        PreferencesKeys.offlineQueue,
        items.map((e) => jsonEncode(e)).toList(),
      );
    }
  }

  static Future<bool> get hasItems async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(PreferencesKeys.offlineQueue) ?? []).isNotEmpty;
  }
}
