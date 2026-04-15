import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';
import 'package:omni_runner/domain/repositories/i_progression_remote_source.dart';

class SupabaseProgressionRemoteSource implements IProgressionRemoteSource {
  static const _tag = 'ProgressionRemoteSource';

  @override
  Future<void> recalculateAndEvaluate(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return;
    try {
      final db = sl<SupabaseClient>();
      await db.rpc('recalculate_profile_progress',
          params: {'p_user_id': userId});
      await db.rpc('evaluate_badges_retroactive',
          params: {'p_user_id': userId});
    } on Exception catch (e) {
      AppLogger.debug('Recalculate/evaluate failed', tag: _tag, error: e);
    }
  }

  @override
  Future<ProfileProgressEntity?> fetchProfileProgress(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return null;
    try {
      final row = await sl<SupabaseClient>()
          .from('profile_progress')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return ProfileProgressEntity(
        userId: userId,
        totalXp: (row['total_xp'] as num?)?.toInt() ?? 0,
        seasonXp: (row['season_xp'] as num?)?.toInt() ?? 0,
        currentSeasonId: row['current_season_id'] as String?,
        dailyStreakCount: (row['daily_streak_count'] as num?)?.toInt() ?? 0,
        streakBest: (row['streak_best'] as num?)?.toInt() ?? 0,
        lastStreakDayMs: (row['last_streak_day_ms'] as num?)?.toInt(),
        hasFreezeAvailable: row['has_freeze_available'] as bool? ?? false,
        weeklySessionCount:
            (row['weekly_session_count'] as num?)?.toInt() ?? 0,
        monthlySessionCount:
            (row['monthly_session_count'] as num?)?.toInt() ?? 0,
        lifetimeSessionCount:
            (row['lifetime_session_count'] as num?)?.toInt() ?? 0,
        lifetimeDistanceM:
            (row['lifetime_distance_m'] as num?)?.toDouble() ?? 0,
        lifetimeMovingMs: (row['lifetime_moving_ms'] as num?)?.toInt() ?? 0,
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<XpTransactionEntity>> fetchXpTransactions(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return const [];
    try {
      final rows = await sl<SupabaseClient>()
          .from('xp_transactions')
          .select('id, user_id, xp, source, ref_id, created_at_ms')
          .eq('user_id', userId)
          .order('created_at_ms', ascending: false)
          .limit(100);
      return rows.map((r) {
        final sourceStr = r['source'] as String? ?? 'session';
        final source = switch (sourceStr) {
          'badge' => XpSource.badge,
          'mission' => XpSource.mission,
          'streak' => XpSource.streak,
          'challenge' => XpSource.challenge,
          _ => XpSource.session,
        };
        return XpTransactionEntity(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          xp: (r['xp'] as num).toInt(),
          source: source,
          refId: r['ref_id'] as String? ?? '',
          createdAtMs: (r['created_at_ms'] as num).toInt(),
        );
      }).toList();
    } on Exception {
      return const [];
    }
  }

  @override
  Future<WeeklyGoalEntity?> fetchWeeklyGoal(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return null;
    try {
      final db = sl<SupabaseClient>();
      final now = DateTime.now().toUtc();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      var rows = await db
          .from('weekly_goals')
          .select()
          .eq('user_id', userId)
          .eq('week_start', weekStartDate)
          .limit(1);

      if (rows.isEmpty) {
        try {
          await db.rpc('generate_weekly_goal', params: {'p_user_id': userId});
          rows = await db
              .from('weekly_goals')
              .select()
              .eq('user_id', userId)
              .eq('week_start', weekStartDate)
              .limit(1);
        } on Exception catch (e) {
          AppLogger.debug('Weekly goals generation failed',
              tag: _tag, error: e);
        }
      }

      if (rows.isEmpty) return null;
      final r = rows.first;
      return WeeklyGoalEntity(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        weekStart: DateTime.parse(r['week_start'] as String),
        metric: (r['metric'] as String) == 'time'
            ? GoalMetric.time
            : GoalMetric.distance,
        targetValue: (r['target_value'] as num).toDouble(),
        currentValue: (r['current_value'] as num).toDouble(),
        status: _parseStatus(r['status'] as String),
        xpAwarded: (r['xp_awarded'] as num?)?.toInt() ?? 0,
        completedAt: r['completed_at'] != null
            ? DateTime.tryParse(r['completed_at'] as String)
            : null,
      );
    } on Exception catch (e) {
      AppLogger.debug('Weekly goal load failed', tag: _tag, error: e);
      return null;
    }
  }

  @override
  Future<({List<Map<String, dynamic>> catalog, Set<String> earnedIds})>
      fetchBadges(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) {
      return (catalog: const <Map<String, dynamic>>[], earnedIds: const <String>{});
    }
    try {
      final db = sl<SupabaseClient>();
      final catalogRows = await db
          .from('badges')
          .select(
              'id, category, tier, name, description, xp_reward, coins_reward, is_secret')
          .order('category')
          .order('tier');
      final awardsRows = await db
          .from('badge_awards')
          .select('badge_id')
          .eq('user_id', userId);
      final catalog = (catalogRows as List<dynamic>)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final earned = (awardsRows as List<dynamic>)
          .map((raw) => (raw as Map<String, dynamic>)['badge_id'] as String)
          .toSet();
      return (catalog: catalog, earnedIds: earned);
    } on Exception catch (e) {
      AppLogger.debug('Badges fetch failed', tag: _tag, error: e);
      return (catalog: const <Map<String, dynamic>>[], earnedIds: const <String>{});
    }
  }

  static GoalStatus _parseStatus(String s) => switch (s) {
        'completed' => GoalStatus.completed,
        'missed' => GoalStatus.missed,
        _ => GoalStatus.active,
      };
}
