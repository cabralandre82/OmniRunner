import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';

sealed class TrainingListState extends Equatable {
  const TrainingListState();

  @override
  List<Object?> get props => [];
}

final class TrainingListInitial extends TrainingListState {
  const TrainingListInitial();
}

final class TrainingListLoading extends TrainingListState {
  const TrainingListLoading();
}

final class TrainingListLoaded extends TrainingListState {
  final List<TrainingSessionEntity> sessions;

  const TrainingListLoaded({required this.sessions});

  @override
  List<Object?> get props => [sessions];
}

final class TrainingListError extends TrainingListState {
  final String message;

  const TrainingListError(this.message);

  @override
  List<Object?> get props => [message];
}
