import 'package:equatable/equatable.dart';

sealed class EventsEvent extends Equatable {
  const EventsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadEvents extends EventsEvent {
  final String userId;
  const LoadEvents(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshEvents extends EventsEvent {
  const RefreshEvents();
}
