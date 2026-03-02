import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_missions_remote_source.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_state.dart';

class MissionsBloc extends Bloc<MissionsEvent, MissionsState> {
  final IMissionProgressRepo _progressRepo;
  final IMissionsRemoteSource _remote;

  String _userId = '';

  MissionsBloc({
    required IMissionProgressRepo progressRepo,
    required IMissionsRemoteSource remote,
  })  : _progressRepo = progressRepo,
        _remote = remote,
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
      // Fetch mission catalog from remote
      final defs = await _remote.fetchMissionDefs();
      final defMap = {for (final d in defs) d.id: d};

      // Sync progress from remote to local repo
      final remoteProgress = await _remote.fetchProgress(_userId);
      for (final p in remoteProgress) {
        await _progressRepo.save(p);
      }

      // Read from local repo (always available, even offline)
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
}
