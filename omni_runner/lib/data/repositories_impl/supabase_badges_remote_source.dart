import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/repositories/i_badges_remote_source.dart';

class SupabaseBadgesRemoteSource implements IBadgesRemoteSource {
  @override
  Future<void> evaluateRetroactive(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return;
    try {
      await sl<SupabaseClient>()
          .rpc('evaluate_badges_retroactive', params: {'p_user_id': userId});
    } on Exception catch (e) {
      AppLogger.debug('Retroactive badge evaluation failed',
          tag: 'BadgesRemoteSource', error: e);
    }
  }

  @override
  Future<List<BadgeEntity>> fetchCatalog() async {
    if (!AppConfig.isSupabaseReady) return const [];
    try {
      final rows = await sl<SupabaseClient>()
          .from('badges')
          .select(
              'id, category, tier, name, description, xp_reward, coins_reward, criteria_type, criteria_json, is_secret')
          .order('category')
          .order('tier');
      return (rows as List<dynamic>).map((raw) {
        final r = raw as Map<String, dynamic>;
        final category = _parseCategory(r['category'] as String? ?? '');
        final tier = _parseTier(r['tier'] as String? ?? '');
        final criteria = _parseCriteria(
          r['criteria_type'] as String? ?? '',
          r['criteria_json'] as Map<String, dynamic>? ?? {},
        );
        return BadgeEntity(
          id: r['id'] as String,
          category: category,
          tier: tier,
          name: r['name'] as String? ?? '',
          description: r['description'] as String? ?? '',
          xpReward: (r['xp_reward'] as num?)?.toInt() ?? 0,
          coinsReward: (r['coins_reward'] as num?)?.toInt() ?? 0,
          criteria: criteria,
          isSecret: r['is_secret'] as bool? ?? false,
        );
      }).toList();
    } on Exception catch (e) {
      AppLogger.debug('Badge catalog fetch failed',
          tag: 'BadgesRemoteSource', error: e);
      return const [];
    }
  }

  @override
  Future<List<BadgeAwardEntity>> fetchAwards(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return const [];
    try {
      final rows = await sl<SupabaseClient>()
          .from('badge_awards')
          .select(
              'id, user_id, badge_id, trigger_session_id, unlocked_at_ms, xp_awarded, coins_awarded')
          .eq('user_id', userId)
          .order('unlocked_at_ms', ascending: false);
      return (rows as List<dynamic>)
          .map((raw) {
            final r = raw as Map<String, dynamic>;
            return BadgeAwardEntity(
              id: r['id'] as String,
              userId: r['user_id'] as String,
              badgeId: r['badge_id'] as String,
              triggerSessionId: r['trigger_session_id'] as String?,
              unlockedAtMs: (r['unlocked_at_ms'] as num).toInt(),
              xpAwarded: (r['xp_awarded'] as num?)?.toInt() ?? 0,
              coinsAwarded: (r['coins_awarded'] as num?)?.toInt() ?? 0,
            );
          })
          .toList();
    } on Exception catch (e) {
      AppLogger.debug('Awards fetch failed',
          tag: 'BadgesRemoteSource', error: e);
      return const [];
    }
  }

  static BadgeCategory _parseCategory(String s) => switch (s) {
        'distance' => BadgeCategory.distance,
        'frequency' => BadgeCategory.frequency,
        'speed' => BadgeCategory.speed,
        'endurance' => BadgeCategory.endurance,
        'social' => BadgeCategory.social,
        _ => BadgeCategory.special,
      };

  static BadgeTier _parseTier(String s) => switch (s) {
        'silver' => BadgeTier.silver,
        'gold' => BadgeTier.gold,
        'diamond' => BadgeTier.diamond,
        _ => BadgeTier.bronze,
      };

  static BadgeCriteria _parseCriteria(
          String type, Map<String, dynamic> json) =>
      switch (type) {
        'single_session_distance' =>
          SingleSessionDistance((json['threshold_m'] as num?)?.toDouble() ?? 0),
        'lifetime_distance' =>
          LifetimeDistance((json['threshold_m'] as num?)?.toDouble() ?? 0),
        'session_count' =>
          SessionCount((json['count'] as num?)?.toInt() ?? 0),
        'daily_streak' => DailyStreak((json['days'] as num?)?.toInt() ?? 0),
        'weekly_distance' =>
          SingleSessionDistance((json['threshold_m'] as num?)?.toDouble() ?? 0),
        'pace_below' => PaceBelow(
            maxPaceSecPerKm:
                (json['max_pace_sec_per_km'] as num?)?.toDouble() ?? 0,
            minDistanceM:
                (json['min_distance_m'] as num?)?.toDouble() ?? 5000,
          ),
        'personal_record_pace' => PersonalRecordPace(
            minDistanceM:
                (json['min_distance_m'] as num?)?.toDouble() ?? 1000),
        'single_session_duration' => SingleSessionDuration(
            (json['threshold_ms'] as num?)?.toInt() ?? 0),
        'lifetime_duration' =>
          LifetimeDuration((json['threshold_ms'] as num?)?.toInt() ?? 0),
        'challenges_completed' =>
          ChallengesCompleted((json['count'] as num?)?.toInt() ?? 0),
        'challenge_won' =>
          ChallengesCompleted((json['count'] as num?)?.toInt() ?? 0),
        'championship_completed' =>
          ChallengesCompleted((json['count'] as num?)?.toInt() ?? 0),
        'consecutive_wins' =>
          ConsecutiveWins((json['count'] as num?)?.toInt() ?? 0),
        'group_leader' =>
          GroupLeader((json['min_participants'] as num?)?.toInt() ?? 5),
        'session_before_hour' =>
          SessionBeforeHour((json['hour_local'] as num?)?.toInt() ?? 6),
        'session_after_hour' =>
          SessionAfterHour((json['hour_local'] as num?)?.toInt() ?? 22),
        _ => const SessionCount(0),
      };
}
