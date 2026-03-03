import 'package:equatable/equatable.dart';

final class WorkoutExecutionEntity extends Equatable {
  final String id;
  final String groupId;
  final String? assignmentId;
  final String athleteUserId;
  final int? actualDurationSeconds;
  final int? actualDistanceMeters;
  final int? avgPace;
  final int? avgHr;
  final int? maxHr;
  final int? calories;
  final String source;
  final DateTime completedAt;

  /// Joined fields (from assignment + template)
  final String? assignmentTemplateName;
  final DateTime? assignmentDate;

  const WorkoutExecutionEntity({
    required this.id,
    required this.groupId,
    this.assignmentId,
    required this.athleteUserId,
    this.actualDurationSeconds,
    this.actualDistanceMeters,
    this.avgPace,
    this.avgHr,
    this.maxHr,
    this.calories,
    required this.source,
    required this.completedAt,
    this.assignmentTemplateName,
    this.assignmentDate,
  });

  @override
  List<Object?> get props => [id, athleteUserId, completedAt];
}
