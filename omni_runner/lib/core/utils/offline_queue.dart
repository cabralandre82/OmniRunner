import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class OfflineQueue {
  static const _key = 'offline_queue';

  static Future<void> enqueue(Map<String, dynamic> task) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_key) ?? [];
    queue.add(jsonEncode(task));
    await prefs.setStringList(_key, queue);
  }

  static Future<List<Map<String, dynamic>>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_key) ?? [];
    await prefs.remove(_key);
    return queue.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  static Future<bool> get hasItems async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).isNotEmpty;
  }
}
