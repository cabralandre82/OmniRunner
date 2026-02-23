import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_race_event_repo.dart';
import 'package:omni_runner/domain/repositories/i_race_participation_repo.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_event.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_state.dart';

class RaceEventsBloc extends Bloc<RaceEventsEvent, RaceEventsState> {
  final IRaceEventRepo _eventRepo;
  final IRaceParticipationRepo _participationRepo;

  String _groupId = '';

  RaceEventsBloc({
    required IRaceEventRepo eventRepo,
    required IRaceParticipationRepo participationRepo,
  })  : _eventRepo = eventRepo,
        _participationRepo = participationRepo,
        super(const RaceEventsInitial()) {
    on<LoadRaceEvents>(_onLoad);
    on<RefreshRaceEvents>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadRaceEvents event,
    Emitter<RaceEventsState> emit,
  ) async {
    _groupId = event.groupId;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshRaceEvents event,
    Emitter<RaceEventsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<RaceEventsState> emit) async {
    emit(const RaceEventsLoading());
    try {
      final events = await _eventRepo.getByGroupId(_groupId);

      if (events.isEmpty) {
        emit(const RaceEventsEmpty());
        return;
      }

      final eventIds = events.map((e) => e.id).toSet();
      final counts = await _participationRepo.countByEventIds(eventIds);

      emit(RaceEventsLoaded(events: events, participantCounts: counts));
    } on Exception catch (e) {
      emit(RaceEventsError('Erro ao carregar eventos: $e'));
    }
  }
}
