import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_state.dart';

class MissionsBloc extends Bloc<MissionsEvent, MissionsState> {
  final IMissionProgressRepo _progressRepo;

  String _userId = '';

  MissionsBloc({
    required IMissionProgressRepo progressRepo,
  })  : _progressRepo = progressRepo,
        super(const MissionsInitial()) {
    on<LoadMissions>(_onLoad);
    on<RefreshMissions>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadMissions event,
    Emitter<MissionsState> emit,
  ) async {
    _userId = event.userId;
    emit(const MissionsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshMissions event,
    Emitter<MissionsState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<MissionsState> emit) async {
    try {
      final defs = await _fetchMissionDefsFromServer();
      await _syncProgressFromServer();
      final defMap = {for (final d in defs) d.id: d};
      final all = await _progressRepo.getByUserId(_userId);
      final active = all
          .where((m) => m.status == MissionProgressStatus.active)
          .toList();
      final completed = all
          .where((m) => m.status == MissionProgressStatus.completed)
          .toList();
      emit(MissionsLoaded(
        active: active,
        completed: completed,
        missionDefs: defMap,
      ));
    } on Exception catch (e) {
      emit(MissionsError('Erro ao carregar missões: $e'));
    }
  }

  Future<List<MissionEntity>> _fetchMissionDefsFromServer() async {
    if (!AppConfig.isSupabaseReady) return const [];
    try {
      final rows = await Supabase.instance.client
          .from('missions')
          .select('id, title, description, difficulty, slot, xp_reward, coins_reward, criteria_type, criteria_json, expires_at_ms, season_id, max_completions, cooldown_ms')
          .order('slot')
          .order('difficulty');
      return (rows as List).map((r) {
        final difficulty = switch (r['difficulty'] as String? ?? 'easy') {
          'medium' => MissionDifficulty.medium,
          'hard' => MissionDifficulty.hard,
          _ => MissionDifficulty.easy,
        };
        final slot = switch (r['slot'] as String? ?? 'daily') {
          'weekly' => MissionSlot.weekly,
          'season' => MissionSlot.season,
          _ => MissionSlot.daily,
        };
        final criteria = _parseCriteria(
          r['criteria_type'] as String? ?? '',
          r['criteria_json'] as Map<String, dynamic>? ?? {},
        );
        return MissionEntity(
          id: r['id'] as String,
          title: r['title'] as String? ?? '',
          description: r['description'] as String? ?? '',
          difficulty: difficulty,
          slot: slot,
          xpReward: (r['xp_reward'] as num?)?.toInt() ?? 0,
          coinsReward: (r['coins_reward'] as num?)?.toInt() ?? 0,
          criteria: criteria,
          expiresAtMs: (r['expires_at_ms'] as num?)?.toInt(),
          seasonId: r['season_id'] as String?,
          maxCompletions: (r['max_completions'] as num?)?.toInt() ?? 1,
          cooldownMs: (r['cooldown_ms'] as num?)?.toInt(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _syncProgressFromServer() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('mission_progress')
          .select('id, user_id, mission_id, status, current_value, target_value, assigned_at_ms, completed_at_ms, completion_count, contributing_session_ids')
          .eq('user_id', _userId);
      for (final r in rows) {
        final statusStr = r['status'] as String? ?? 'active';
        final status = switch (statusStr) {
          'completed' => MissionProgressStatus.completed,
          'expired' => MissionProgressStatus.expired,
          _ => MissionProgressStatus.active,
        };
        final sessionIds = (r['contributing_session_ids'] as List<dynamic>?)
            ?.cast<String>() ?? [];
        final progress = MissionProgressEntity(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          missionId: r['mission_id'] as String,
          status: status,
          currentValue: (r['current_value'] as num).toDouble(),
          targetValue: (r['target_value'] as num).toDouble(),
          assignedAtMs: (r['assigned_at_ms'] as num).toInt(),
          completedAtMs: (r['completed_at_ms'] as num?)?.toInt(),
          completionCount: (r['completion_count'] as num?)?.toInt() ?? 0,
          contributingSessionIds: sessionIds,
        );
        await _progressRepo.save(progress);
      }
    } catch (_) {
      // Offline — use local data
    }
  }

  static MissionCriteria _parseCriteria(String type, Map<String, dynamic> json) =>
      switch (type) {
        'accumulate_distance' =>
          AccumulateDistance((json['target_m'] as num?)?.toDouble() ?? 0),
        'complete_sessions' =>
          CompleteSessionCount((json['target_count'] as num?)?.toInt() ?? 0),
        'achieve_pace' => AchievePaceTarget(
            maxPaceSecPerKm: (json['max_pace_sec_per_km'] as num?)?.toDouble() ?? 0,
            minDistanceM: (json['min_distance_m'] as num?)?.toDouble() ?? 5000,
          ),
        'single_session_duration' =>
          SingleSessionDurationTarget((json['target_ms'] as num?)?.toInt() ?? 0),
        'hr_zone_time' => HrZoneTime(
            zoneIndex: (json['zone_index'] as num?)?.toInt() ?? 1,
            targetMs: (json['target_ms'] as num?)?.toInt() ?? 0,
          ),
        'maintain_streak' =>
          MaintainStreak((json['days'] as num?)?.toInt() ?? 0),
        'complete_challenges' =>
          CompleteChallenges((json['count'] as num?)?.toInt() ?? 0),
        _ => const CompleteSessionCount(1),
      };
}
