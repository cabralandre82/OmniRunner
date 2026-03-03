import 'package:equatable/equatable.dart';

sealed class TrainingDetailEvent extends Equatable {
  const TrainingDetailEvent();

  @override
  List<Object?> get props => [];
}

final class LoadTrainingDetail extends TrainingDetailEvent {
  final String sessionId;

  const LoadTrainingDetail({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}

final class RefreshTrainingDetail extends TrainingDetailEvent {
  const RefreshTrainingDetail();
}

final class CancelTraining extends TrainingDetailEvent {
  const CancelTraining();
}

final class AttendanceMarked extends TrainingDetailEvent {
  final String athleteName;

  const AttendanceMarked({required this.athleteName});

  @override
  List<Object?> get props => [athleteName];
}
