import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';

class ProgressionBloc extends Bloc<ProgressionEvent, ProgressionState> {
  final IProfileProgressRepo _profileRepo;
  final IXpTransactionRepo _xpRepo;

  String _userId = '';

  ProgressionBloc({
    required IProfileProgressRepo profileRepo,
    required IXpTransactionRepo xpRepo,
  })  : _profileRepo = profileRepo,
        _xpRepo = xpRepo,
        super(const ProgressionInitial()) {
    on<LoadProgression>(_onLoad);
    on<RefreshProgression>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    _userId = event.userId;
    emit(const ProgressionLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<ProgressionState> emit) async {
    try {
      await _recalculateAndEvaluate();
      await _syncProfileProgress();
      await _syncXpTransactions();
      final profile = await _profileRepo.getByUserId(_userId);
      final xpHistory = await _xpRepo.getByUserId(_userId);
      final weeklyGoal = await _fetchWeeklyGoal();
      final badges = await _fetchBadges();
      emit(ProgressionLoaded(
        profile: profile,
        recentXp: xpHistory,
        weeklyGoal: weeklyGoal,
        badgeCatalog: badges.$1,
        earnedBadgeIds: badges.$2,
      ));
    } on Exception catch (e) {
      emit(ProgressionError('Erro ao carregar progressão: $e'));
    }
  }

  Future<void> _syncProfileProgress() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('profile_progress')
          .select()
          .eq('user_id', _userId)
          .maybeSingle();
      if (row == null) return;
      final remote = ProfileProgressEntity(
        userId: _userId,
        totalXp: (row['total_xp'] as num?)?.toInt() ?? 0,
        seasonXp: (row['season_xp'] as num?)?.toInt() ?? 0,
        currentSeasonId: row['current_season_id'] as String?,
        dailyStreakCount: (row['daily_streak_count'] as num?)?.toInt() ?? 0,
        streakBest: (row['streak_best'] as num?)?.toInt() ?? 0,
        lastStreakDayMs: (row['last_streak_day_ms'] as num?)?.toInt(),
        hasFreezeAvailable: row['has_freeze_available'] as bool? ?? false,
        weeklySessionCount: (row['weekly_session_count'] as num?)?.toInt() ?? 0,
        monthlySessionCount: (row['monthly_session_count'] as num?)?.toInt() ?? 0,
        lifetimeSessionCount: (row['lifetime_session_count'] as num?)?.toInt() ?? 0,
        lifetimeDistanceM: (row['lifetime_distance_m'] as num?)?.toDouble() ?? 0,
        lifetimeMovingMs: (row['lifetime_moving_ms'] as num?)?.toInt() ?? 0,
      );
      await _profileRepo.save(remote);
    } on Exception {
      // Offline — use local data
    }
  }

  Future<void> _syncXpTransactions() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('xp_transactions')
          .select('id, user_id, xp, source, ref_id, created_at_ms')
          .eq('user_id', _userId)
          .order('created_at_ms', ascending: false)
          .limit(100);
      for (final r in rows) {
        final sourceStr = r['source'] as String? ?? 'session';
        final source = switch (sourceStr) {
          'badge' => XpSource.badge,
          'mission' => XpSource.mission,
          'streak' => XpSource.streak,
          'challenge' => XpSource.challenge,
          _ => XpSource.session,
        };
        final tx = XpTransactionEntity(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          xp: (r['xp'] as num).toInt(),
          source: source,
          refId: r['ref_id'] as String? ?? '',
          createdAtMs: (r['created_at_ms'] as num).toInt(),
        );
        await _xpRepo.append(tx);
      }
    } on Exception {
      // Offline — use local data
    }
  }

  Future<WeeklyGoalEntity?> _fetchWeeklyGoal() async {
    try {
      final db = Supabase.instance.client;
      final now = DateTime.now().toUtc();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      var rows = await db
          .from('weekly_goals')
          .select()
          .eq('user_id', _userId)
          .eq('week_start', weekStartDate)
          .limit(1);

      if (rows.isEmpty) {
        try {
          await db.rpc('generate_weekly_goal', params: {'p_user_id': _userId});
          rows = await db
              .from('weekly_goals')
              .select()
              .eq('user_id', _userId)
              .eq('week_start', weekStartDate)
              .limit(1);
        } catch (_) {}
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
    } catch (_) {
      return null;
    }
  }

  /// Recalculate profile progress and retroactively evaluate badges.
  Future<void> _recalculateAndEvaluate() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final db = Supabase.instance.client;
      await db.rpc('recalculate_profile_progress', params: {'p_user_id': _userId});
      await db.rpc('evaluate_badges_retroactive', params: {'p_user_id': _userId});
    } catch (_) {}
  }

  /// Fetch badge catalog and user's earned badges from Supabase.
  Future<(List<Map<String, dynamic>>, Set<String>)> _fetchBadges() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) {
      return (const <Map<String, dynamic>>[], const <String>{});
    }
    try {
      final db = Supabase.instance.client;
      final catalogRows = await db
          .from('badges')
          .select('id, category, tier, name, description, xp_reward, coins_reward, is_secret')
          .order('category')
          .order('tier');
      final awardsRows = await db
          .from('badge_awards')
          .select('badge_id')
          .eq('user_id', _userId);
      final catalog = List<Map<String, dynamic>>.from(catalogRows as List);
      final earned = (awardsRows as List)
          .map((r) => r['badge_id'] as String)
          .toSet();
      return (catalog, earned);
    } catch (_) {
      return (const <Map<String, dynamic>>[], const <String>{});
    }
  }

  static GoalStatus _parseStatus(String s) => switch (s) {
        'completed' => GoalStatus.completed,
        'missed' => GoalStatus.missed,
        _ => GoalStatus.active,
      };
}
