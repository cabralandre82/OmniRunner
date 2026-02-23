import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';

sealed class MissionsState extends Equatable {
  const MissionsState();

  @override
  List<Object?> get props => [];
}

final class MissionsInitial extends MissionsState {
  const MissionsInitial();
}

final class MissionsLoading extends MissionsState {
  const MissionsLoading();
}

final class MissionsLoaded extends MissionsState {
  final List<MissionProgressEntity> active;
  final List<MissionProgressEntity> completed;

  /// Maps missionId → MissionEntity definition for title/description lookup.
  final Map<String, MissionEntity> missionDefs;

  const MissionsLoaded({
    required this.active,
    required this.completed,
    this.missionDefs = const {},
  });

  @override
  List<Object?> get props => [active, completed, missionDefs];
}

final class MissionsError extends MissionsState {
  final String message;

  const MissionsError(this.message);

  @override
  List<Object?> get props => [message];
}
