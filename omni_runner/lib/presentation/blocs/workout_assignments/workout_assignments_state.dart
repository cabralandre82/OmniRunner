import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';

sealed class WorkoutAssignmentsState extends Equatable {
  const WorkoutAssignmentsState();

  @override
  List<Object?> get props => [];
}

final class AssignmentsInitial extends WorkoutAssignmentsState {
  const AssignmentsInitial();
}

final class AssignmentsLoading extends WorkoutAssignmentsState {
  const AssignmentsLoading();
}

final class AssignmentsLoaded extends WorkoutAssignmentsState {
  final List<WorkoutAssignmentEntity> assignments;

  const AssignmentsLoaded({required this.assignments});

  @override
  List<Object?> get props => [assignments];
}

final class AssignmentsError extends WorkoutAssignmentsState {
  final String message;

  const AssignmentsError(this.message);

  @override
  List<Object?> get props => [message];
}
