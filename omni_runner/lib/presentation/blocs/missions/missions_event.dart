import 'package:equatable/equatable.dart';

sealed class MissionsEvent extends Equatable {
  const MissionsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadMissions extends MissionsEvent {
  final String userId;
  const LoadMissions(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshMissions extends MissionsEvent {
  const RefreshMissions();
}
