import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';
import 'package:omni_runner/domain/entities/race_result_entity.dart';

sealed class RaceEventDetailsState extends Equatable {
  const RaceEventDetailsState();

  @override
  List<Object?> get props => [];
}

final class RaceEventDetailsInitial extends RaceEventDetailsState {
  const RaceEventDetailsInitial();
}

final class RaceEventDetailsLoading extends RaceEventDetailsState {
  const RaceEventDetailsLoading();
}

final class RaceEventDetailsLoaded extends RaceEventDetailsState {
  final RaceEventEntity event;
  final List<RaceParticipationEntity> participations;
  final RaceParticipationEntity? myParticipation;
  final List<RaceResultEntity> results;
  final RaceResultEntity? myResult;
  final String currentUserId;

  const RaceEventDetailsLoaded({
    required this.event,
    required this.participations,
    this.myParticipation,
    required this.results,
    this.myResult,
    required this.currentUserId,
  });

  bool get isCompleted => event.status == RaceEventStatus.completed;

  @override
  List<Object?> get props => [
        event,
        participations,
        myParticipation,
        results,
        myResult,
        currentUserId,
      ];
}

final class RaceEventDetailsError extends RaceEventDetailsState {
  final String message;
  const RaceEventDetailsError(this.message);

  @override
  List<Object?> get props => [message];
}
