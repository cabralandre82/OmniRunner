import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/service_locator.dart';

/// In-memory cache for the current user's coaching_members data.
///
/// Registered as a singleton via GetIt. Avoids repeated Supabase queries
/// for membership data that rarely changes during a session.
/// TTL: 5 minutes.
class MembershipCache {
  static const _ttl = Duration(minutes: 5);

  List<Map<String, dynamic>>? _cachedMemberships;
  DateTime? _cacheTime;
  String? _cachedUserId;

  Future<List<Map<String, dynamic>>> getMemberships({
    required String userId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedMemberships != null &&
        _cachedUserId == userId &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _ttl) {
      return _cachedMemberships!;
    }

    final rows = await sl<SupabaseClient>()
        .from('coaching_members')
        .select('id, user_id, group_id, display_name, role, joined_at_ms')
        .eq('user_id', userId);

    _cachedMemberships =
        List<Map<String, dynamic>>.from((rows as List).cast<Map<String, dynamic>>());
    _cacheTime = DateTime.now();
    _cachedUserId = userId;
    return _cachedMemberships!;
  }

  void invalidate() {
    _cachedMemberships = null;
    _cacheTime = null;
    _cachedUserId = null;
  }
}
