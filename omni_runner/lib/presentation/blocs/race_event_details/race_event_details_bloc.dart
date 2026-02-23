import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_result_entity.dart';
import 'package:omni_runner/domain/repositories/i_race_event_repo.dart';
import 'package:omni_runner/domain/repositories/i_race_participation_repo.dart';
import 'package:omni_runner/domain/repositories/i_race_result_repo.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_event.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_state.dart';

class RaceEventDetailsBloc
    extends Bloc<RaceEventDetailsEvent, RaceEventDetailsState> {
  final IRaceEventRepo _eventRepo;
  final IRaceParticipationRepo _participationRepo;
  final IRaceResultRepo _resultRepo;

  String _raceEventId = '';
  String _currentUserId = '';

  RaceEventDetailsBloc({
    required IRaceEventRepo eventRepo,
    required IRaceParticipationRepo participationRepo,
    required IRaceResultRepo resultRepo,
  })  : _eventRepo = eventRepo,
        _participationRepo = participationRepo,
        _resultRepo = resultRepo,
        super(const RaceEventDetailsInitial()) {
    on<LoadRaceEventDetails>(_onLoad);
    on<RefreshRaceEventDetails>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadRaceEventDetails event,
    Emitter<RaceEventDetailsState> emit,
  ) async {
    _raceEventId = event.raceEventId;
    _currentUserId = event.currentUserId;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshRaceEventDetails event,
    Emitter<RaceEventDetailsState> emit,
  ) async {
    if (_raceEventId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<RaceEventDetailsState> emit) async {
    emit(const RaceEventDetailsLoading());
    try {
      final raceEvent = await _eventRepo.getById(_raceEventId);
      if (raceEvent == null) {
        emit(const RaceEventDetailsError('Evento não encontrado.'));
        return;
      }

      final participations =
          await _participationRepo.getByEventId(_raceEventId);
      final myParticipation = await _participationRepo.getByEventAndUser(
        raceEventId: _raceEventId,
        userId: _currentUserId,
      );

      final isCompleted = raceEvent.status == RaceEventStatus.completed;
      final results = isCompleted
          ? await _resultRepo.getByEventId(_raceEventId)
          : <RaceResultEntity>[];
      final myResult = isCompleted
          ? await _resultRepo.getByEventAndUser(
              raceEventId: _raceEventId,
              userId: _currentUserId,
            )
          : null;

      emit(RaceEventDetailsLoaded(
        event: raceEvent,
        participations: participations,
        myParticipation: myParticipation,
        results: results,
        myResult: myResult,
        currentUserId: _currentUserId,
      ));
    } on Exception catch (e) {
      emit(RaceEventDetailsError('Erro ao carregar evento: $e'));
    }
  }
}
