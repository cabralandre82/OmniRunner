import 'package:equatable/equatable.dart';

sealed class RaceEventDetailsEvent extends Equatable {
  const RaceEventDetailsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadRaceEventDetails extends RaceEventDetailsEvent {
  final String raceEventId;
  final String currentUserId;

  const LoadRaceEventDetails({
    required this.raceEventId,
    required this.currentUserId,
  });

  @override
  List<Object?> get props => [raceEventId, currentUserId];
}

final class RefreshRaceEventDetails extends RaceEventDetailsEvent {
  const RefreshRaceEventDetails();
}
