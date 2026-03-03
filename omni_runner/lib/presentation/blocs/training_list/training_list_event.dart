import 'package:equatable/equatable.dart';

sealed class TrainingListEvent extends Equatable {
  const TrainingListEvent();

  @override
  List<Object?> get props => [];
}

final class LoadTrainingSessions extends TrainingListEvent {
  final String groupId;
  final DateTime? from;
  final DateTime? to;

  const LoadTrainingSessions({
    required this.groupId,
    this.from,
    this.to,
  });

  @override
  List<Object?> get props => [groupId, from, to];
}

final class RefreshTrainingSessions extends TrainingListEvent {
  const RefreshTrainingSessions();
}
