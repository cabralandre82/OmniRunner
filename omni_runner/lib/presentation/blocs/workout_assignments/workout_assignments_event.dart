import 'package:equatable/equatable.dart';

sealed class WorkoutAssignmentsEvent extends Equatable {
  const WorkoutAssignmentsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadAssignments extends WorkoutAssignmentsEvent {
  final String groupId;
  final DateTime? from;
  final DateTime? to;

  const LoadAssignments({required this.groupId, this.from, this.to});

  @override
  List<Object?> get props => [groupId, from, to];
}

final class RefreshAssignments extends WorkoutAssignmentsEvent {
  const RefreshAssignments();
}

final class AssignWorkout extends WorkoutAssignmentsEvent {
  final String templateId;
  final String athleteUserId;
  final DateTime date;
  final String? notes;

  const AssignWorkout({
    required this.templateId,
    required this.athleteUserId,
    required this.date,
    this.notes,
  });

  @override
  List<Object?> get props => [templateId, athleteUserId, date, notes];
}
