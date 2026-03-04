import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_runner/core/cache/cache_ttl_config.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';

/// Stores last-cached timestamps for Isar cache entries.
///
/// When writing to Isar cache, call [recordCacheWrite]. When reading,
/// call [isStale] to determine if data should be refetched from backend.
class CacheMetadataStore {

  final SharedPreferences _prefs;

  CacheMetadataStore(this._prefs);

  /// Records that cache [key] was written at the current time.
  /// [key] should be unique per entity type, e.g. 'profile_progress', 'wallet'.
  Future<void> recordCacheWrite(String key, [String? userId]) async {
    final k = _key(key, userId);
    await _prefs.setInt(k, DateTime.now().millisecondsSinceEpoch);
  }

  void recordCacheWriteSync(String key, [String? userId]) {
    final k = _key(key, userId);
    _prefs.setInt(k, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns true if the cache for [key] is stale (older than [ttlMs]).
  /// If no timestamp exists, returns true (treat as stale).
  bool isStale(String key, [String? userId, int ttlMs = CacheTtlConfig.defaultTtlMs]) {
    final k = _key(key, userId);
    final ts = _prefs.getInt(k);
    if (ts == null) return true;
    return DateTime.now().millisecondsSinceEpoch - ts > ttlMs;
  }

  String _key(String key, String? userId) {
    if (userId != null) return '${PreferencesKeys.cacheMetaPrefix}${key}_$userId';
    return '${PreferencesKeys.cacheMetaPrefix}$key';
  }
}
