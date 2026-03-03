import 'package:equatable/equatable.dart';

enum WorkoutAssignmentStatus { planned, completed, missed }

String assignmentStatusToString(WorkoutAssignmentStatus s) => switch (s) {
      WorkoutAssignmentStatus.planned => 'planned',
      WorkoutAssignmentStatus.completed => 'completed',
      WorkoutAssignmentStatus.missed => 'missed',
    };

WorkoutAssignmentStatus assignmentStatusFromString(String s) => switch (s) {
      'completed' => WorkoutAssignmentStatus.completed,
      'missed' => WorkoutAssignmentStatus.missed,
      _ => WorkoutAssignmentStatus.planned,
    };

final class WorkoutAssignmentEntity extends Equatable {
  final String id;
  final String groupId;
  final String athleteUserId;
  final String templateId;
  final DateTime scheduledDate;
  final WorkoutAssignmentStatus status;
  final int version;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final String? templateName;
  final String? athleteDisplayName;

  const WorkoutAssignmentEntity({
    required this.id,
    required this.groupId,
    required this.athleteUserId,
    required this.templateId,
    required this.scheduledDate,
    required this.status,
    this.version = 1,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    this.templateName,
    this.athleteDisplayName,
  });

  @override
  List<Object?> get props => [id, athleteUserId, scheduledDate];
}
