import 'package:omni_runner/core/logging/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight feature flag service backed by the `feature_flags` table.
///
/// Loads all flags once at startup, caches in memory.
/// Call [refresh] to re-fetch (e.g. on pull-to-refresh or periodic timer).
///
/// Rollout is deterministic per user: uses a hash of `userId + flagKey`
/// to decide if the user falls within [rollout_pct].
class FeatureFlagService {
  FeatureFlagService({required this.userId});

  final String userId;
  Map<String, _Flag> _flags = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Loads flags from Supabase. Safe to call multiple times.
  Future<void> load() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('feature_flags')
          .select('key, enabled, rollout_pct')
          .order('key');

      final map = <String, _Flag>{};
      for (final row in rows) {
        map[row['key'] as String] = _Flag(
          enabled: row['enabled'] as bool,
          rolloutPct: row['rollout_pct'] as int,
        );
      }
      _flags = map;
      _loaded = true;
    } on Exception catch (e) {
      AppLogger.warn('Failed to load feature flags', tag: 'FeatureFlags', error: e);
    }
  }

  /// Alias for [load] — re-fetches from server.
  Future<void> refresh() => load();

  /// Returns `true` if the flag is enabled for this user.
  ///
  /// Unknown flags default to `false`.
  bool isEnabled(String key) {
    final flag = _flags[key];
    if (flag == null || !flag.enabled) return false;
    if (flag.rolloutPct >= 100) return true;
    if (flag.rolloutPct <= 0) return false;
    return _userBucket(key) < flag.rolloutPct;
  }

  /// Deterministic bucket 0–99 based on userId + flagKey.
  int _userBucket(String key) {
    final hash = '$userId:$key'.hashCode.abs();
    return hash % 100;
  }
}

class _Flag {
  const _Flag({required this.enabled, required this.rolloutPct});
  final bool enabled;
  final int rolloutPct;
}
