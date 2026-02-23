import 'package:equatable/equatable.dart';

sealed class RaceEventsEvent extends Equatable {
  const RaceEventsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadRaceEvents extends RaceEventsEvent {
  final String groupId;
  const LoadRaceEvents({required this.groupId});

  @override
  List<Object?> get props => [groupId];
}

final class RefreshRaceEvents extends RaceEventsEvent {
  const RefreshRaceEvents();
}
