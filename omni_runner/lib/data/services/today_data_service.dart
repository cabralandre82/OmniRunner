import 'package:supabase_flutter/supabase_flutter.dart';

/// Service wrapping Supabase calls used by [TodayScreen].
/// Reduces direct Supabase usage in the presentation layer.
class TodayDataService {
  TodayDataService(this._client);

  final SupabaseClient _client;

  /// Triggers profile progress recalculation on the backend.
  Future<void> recalculateProfileProgress(String userId) async {
    await _client.rpc(
      'recalculate_profile_progress',
      params: {'p_user_id': userId},
    );
  }

  /// Fetches profile progress row for the given user.
  Future<Map<String, dynamic>?> getProfileProgress(String userId) async {
    final row = await _client
        .from('profile_progress')
        .select(
          'user_id, total_xp, season_xp, current_season_id, daily_streak_count, '
          'streak_best, last_streak_day_ms, has_freeze_available, '
          'weekly_session_count, monthly_session_count, lifetime_session_count, '
          'lifetime_distance_m, lifetime_moving_ms',
        )
        .eq('user_id', userId)
        .maybeSingle();
    return row != null ? Map<String, dynamic>.from(row) : null;
  }

  /// Fetches completed sessions from Supabase for the user (>= 1km).
  Future<List<Map<String, dynamic>>> getRemoteSessions(String userId) async {
    final rows = await _client
        .from('sessions')
        .select(
          'id, user_id, status, start_time_ms, end_time_ms, total_distance_m, '
          'is_verified, integrity_flags, avg_bpm, max_bpm, source',
        )
        .eq('user_id', userId)
        .eq('status', 3)
        .gte('total_distance_m', 1000)
        .order('start_time_ms', ascending: false)
        .limit(5);
    return List<Map<String, dynamic>>.from(
      (rows as List<dynamic>).map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>)),
    );
  }

  /// Fetches active challenge IDs for the user.
  Future<List<String>> getActiveChallengeIds(String userId) async {
    final myParts = await _client
        .from('challenge_participants')
        .select('challenge_id')
        .eq('user_id', userId)
        .inFilter('status', ['accepted', 'invited']);
    return (myParts as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['challenge_id'] as String)
        .toList();
  }

  /// Fetches active challenge rows by IDs.
  Future<List<Map<String, dynamic>>> getChallengesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('challenges')
        .select('id, title, type, status, ends_at_ms, entry_fee_coins')
        .inFilter('id', ids)
        .eq('status', 'active');
    return List<Map<String, dynamic>>.from(
      (rows as List<dynamic>).map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>)),
    );
  }

  /// Fetches active championship IDs for the user.
  Future<List<String>> getActiveChampionshipIds(String userId) async {
    final parts = await _client
        .from('championship_participants')
        .select('championship_id')
        .eq('user_id', userId);
    return (parts as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)['championship_id'] as String)
        .toList();
  }

  /// Fetches active championship rows by IDs.
  Future<List<Map<String, dynamic>>> getChampionshipsByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('championships')
        .select('id, name, status')
        .inFilter('id', ids)
        .eq('status', 'active');
    return List<Map<String, dynamic>>.from(
      (rows as List<dynamic>).map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>)),
    );
  }

  /// Fetches journal entry for a session.
  Future<Map<String, dynamic>?> getJournalEntry(
    String sessionId,
    String userId,
  ) async {
    final row = await _client
        .from('session_journal_entries')
        .select('notes, mood_emoji')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null ? Map<String, dynamic>.from(row) : null;
  }

  /// Saves or updates journal entry for a session.
  Future<void> upsertJournalEntry({
    required String sessionId,
    required String userId,
    String? notes,
    String? moodEmoji,
  }) async {
    await _client.from('session_journal_entries').upsert(
      {
        'session_id': sessionId,
        'user_id': userId,
        'notes': notes,
        'mood_emoji': moodEmoji,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'session_id',
    );
  }
}
