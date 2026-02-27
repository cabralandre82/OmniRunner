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
  final List<MissionEntity> Function() _activeMissionDefs;

  String _userId = '';

  MissionsBloc({
    required IMissionProgressRepo progressRepo,
    required List<MissionEntity> Function() activeMissionDefs,
  })  : _progressRepo = progressRepo,
        _activeMissionDefs = activeMissionDefs,
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
      await _syncFromServer();
      final defs = _activeMissionDefs();
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

  Future<void> _syncFromServer() async {
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
    } on Exception {
      // Offline — use local data
    }
  }
}
