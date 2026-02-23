import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';

sealed class EventsState extends Equatable {
  const EventsState();

  @override
  List<Object?> get props => [];
}

final class EventsInitial extends EventsState {
  const EventsInitial();
}

final class EventsLoading extends EventsState {
  const EventsLoading();
}

final class EventsLoaded extends EventsState {
  final List<EventEntity> activeEvents;
  final List<EventEntity> upcomingEvents;
  final List<EventEntity> completedEvents;

  /// Maps eventId → user's participation (null if not joined).
  final Map<String, EventParticipationEntity> participations;

  const EventsLoaded({
    this.activeEvents = const [],
    this.upcomingEvents = const [],
    this.completedEvents = const [],
    this.participations = const {},
  });

  bool isJoined(String eventId) => participations.containsKey(eventId);

  @override
  List<Object?> get props =>
      [activeEvents, upcomingEvents, completedEvents, participations];
}

final class EventsError extends EventsState {
  final String message;
  const EventsError(this.message);

  @override
  List<Object?> get props => [message];
}
