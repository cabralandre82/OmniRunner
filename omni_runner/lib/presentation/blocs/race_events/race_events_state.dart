import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';

sealed class RaceEventsState extends Equatable {
  const RaceEventsState();

  @override
  List<Object?> get props => [];
}

final class RaceEventsInitial extends RaceEventsState {
  const RaceEventsInitial();
}

final class RaceEventsLoading extends RaceEventsState {
  const RaceEventsLoading();
}

final class RaceEventsLoaded extends RaceEventsState {
  final List<RaceEventEntity> events;
  final Map<String, int> participantCounts;

  const RaceEventsLoaded({
    required this.events,
    required this.participantCounts,
  });

  @override
  List<Object?> get props => [events, participantCounts];
}

final class RaceEventsEmpty extends RaceEventsState {
  const RaceEventsEmpty();
}

final class RaceEventsError extends RaceEventsState {
  final String message;
  const RaceEventsError(this.message);

  @override
  List<Object?> get props => [message];
}
