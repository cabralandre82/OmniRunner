import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';

class SupabaseTrainingPlanRepo implements ITrainingPlanRepo {
  SupabaseTrainingPlanRepo(this._client);

  final SupabaseClient _client;

  static const _tag = 'TrainingPlanRepo';

  // ── Sync delta ────────────────────────────────────────────────────────────

  @override
  Future<SyncDeltaResult> getSyncDelta({
    required String deviceId,
    DateTime? since,
  }) async {
    try {
      final sinceStr = (since ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toUtc()
          .toIso8601String();

      final result = await _client.rpc('fn_get_training_sync_delta', params: {
        'p_device_id': deviceId,
        'p_since':     sinceStr,
      });

      final data = result as Map<String, dynamic>;
      final rawWorkouts = (data['workouts'] as List<dynamic>?) ?? [];
      final cursorStr = (data['cursor'] as String?) ?? sinceStr;

      final workouts = rawWorkouts
          .map((w) => PlanWorkoutEntity.fromJson(w as Map<String, dynamic>))
          .toList();

      return SyncDeltaResult(
        workouts: workouts,
        cursor:   DateTime.tryParse(cursorStr) ?? DateTime.fromMillisecondsSinceEpoch(0),
        count:    workouts.length,
      );
    } catch (e, stack) {
      AppLogger.error('getSyncDelta failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }

  // ── Workouts for period ───────────────────────────────────────────────────

  @override
  Future<List<PlanWorkoutEntity>> getWorkoutsForPeriod({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final fromStr = from.toIso8601String().split('T')[0];
      final toStr   = to.toIso8601String().split('T')[0];

      final rows = await _client
          .from('plan_workout_releases')
          .select('''
            id, scheduled_date, workout_order, release_status, workout_type,
            workout_label, coach_notes, content_version,
            content_snapshot, released_at, cancelled_at, replaced_by_id, updated_at,
            completed_workouts!inner (
              id, actual_distance_m, actual_duration_s,
              actual_avg_pace_s_km, actual_avg_hr, perceived_effort, finished_at
            ),
            athlete_workout_feedback (rating, mood, how_was_it)
          ''')
          .gte('scheduled_date', fromStr)
          .lte('scheduled_date', toStr)
          .inFilter('release_status', ['released', 'in_progress', 'completed', 'cancelled', 'replaced'])
          .order('scheduled_date')
          .order('workout_order');

      return (rows as List<dynamic>)
          .map((r) => PlanWorkoutEntity.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      AppLogger.error('getWorkoutsForPeriod failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }

  // ── Single workout ────────────────────────────────────────────────────────

  @override
  Future<PlanWorkoutEntity?> getWorkoutById(String releaseId) async {
    try {
      final row = await _client
          .from('plan_workout_releases')
          .select('''
            id, scheduled_date, workout_order, release_status, workout_type,
            workout_label, coach_notes, content_version,
            content_snapshot, released_at, cancelled_at, replaced_by_id, updated_at,
            completed_workouts (
              id, actual_distance_m, actual_duration_s,
              actual_avg_pace_s_km, actual_avg_hr, perceived_effort, finished_at
            ),
            athlete_workout_feedback (rating, mood, how_was_it)
          ''')
          .eq('id', releaseId)
          .maybeSingle();

      if (row == null) return null;
      return PlanWorkoutEntity.fromJson(row);
    } catch (e, stack) {
      AppLogger.error('getWorkoutById failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }

  // ── Start workout ─────────────────────────────────────────────────────────

  @override
  Future<void> startWorkout(String releaseId) async {
    try {
      await _client.rpc('fn_athlete_start_workout', params: {
        'p_release_id': releaseId,
      });
    } catch (e, stack) {
      AppLogger.error('startWorkout failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }

  // ── Complete workout ──────────────────────────────────────────────────────

  @override
  Future<String> completeWorkout({
    required String releaseId,
    double? actualDistanceM,
    int? actualDurationS,
    double? actualAvgHr,
    int? perceivedEffort,
    int? mood,
    String source = 'manual',
  }) async {
    try {
      final result = await _client.rpc('fn_athlete_complete_workout', params: {
        'p_release_id':        releaseId,
        'p_actual_distance_m': actualDistanceM,
        'p_actual_duration_s': actualDurationS,
        'p_actual_avg_hr':     actualAvgHr,
        'p_perceived_effort':  perceivedEffort,
        'p_mood':              mood,
        'p_source':            source,
      });
      return (result as String?) ?? '';
    } catch (e, stack) {
      AppLogger.error('completeWorkout failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }

  // ── Submit feedback ───────────────────────────────────────────────────────

  @override
  Future<String> submitFeedback({
    required String releaseId,
    int? rating,
    int? perceivedEffort,
    int? mood,
    String? howWasIt,
    String? whatWasHard,
    String? notes,
  }) async {
    try {
      final result = await _client.rpc('fn_submit_workout_feedback', params: {
        'p_release_id':       releaseId,
        'p_rating':           rating,
        'p_perceived_effort': perceivedEffort,
        'p_mood':             mood,
        'p_how_was_it':       howWasIt,
        'p_what_was_hard':    whatWasHard,
        'p_notes':            notes,
      });
      return (result as String?) ?? '';
    } catch (e, stack) {
      AppLogger.error('submitFeedback failed', tag: _tag, error: e, stack: stack);
      rethrow;
    }
  }
}
