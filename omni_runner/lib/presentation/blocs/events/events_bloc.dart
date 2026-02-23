import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';
import 'package:omni_runner/presentation/blocs/events/events_event.dart';
import 'package:omni_runner/presentation/blocs/events/events_state.dart';

class EventsBloc extends Bloc<EventsEvent, EventsState> {
  final IEventRepo _eventRepo;

  String _userId = '';

  EventsBloc({required IEventRepo eventRepo})
      : _eventRepo = eventRepo,
        super(const EventsInitial()) {
    on<LoadEvents>(_onLoad);
    on<RefreshEvents>(_onRefresh);
  }

  Future<void> _onLoad(LoadEvents event, Emitter<EventsState> emit) async {
    _userId = event.userId;
    emit(const EventsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
      RefreshEvents event, Emitter<EventsState> emit) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<EventsState> emit) async {
    try {
      final active = await _eventRepo.getEventsByStatus(EventStatus.active);
      final upcoming =
          await _eventRepo.getEventsByStatus(EventStatus.upcoming);
      final completed =
          await _eventRepo.getEventsByStatus(EventStatus.completed);

      final userParticipations =
          await _eventRepo.getParticipationsByUser(_userId);
      final participationMap = <String, EventParticipationEntity>{
        for (final p in userParticipations) p.eventId: p,
      };

      emit(EventsLoaded(
        activeEvents: active,
        upcomingEvents: upcoming,
        completedEvents: completed,
        participations: participationMap,
      ));
    } on Exception catch (e) {
      emit(EventsError('Erro ao carregar eventos: $e'));
    }
  }
}
