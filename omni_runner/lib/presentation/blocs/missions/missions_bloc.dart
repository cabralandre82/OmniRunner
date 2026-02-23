import 'package:flutter_bloc/flutter_bloc.dart';
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
}
