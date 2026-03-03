import 'package:equatable/equatable.dart';

enum WorkoutBlockType { warmup, interval, recovery, cooldown, steady }

String workoutBlockTypeToString(WorkoutBlockType t) => switch (t) {
      WorkoutBlockType.warmup => 'warmup',
      WorkoutBlockType.interval => 'interval',
      WorkoutBlockType.recovery => 'recovery',
      WorkoutBlockType.cooldown => 'cooldown',
      WorkoutBlockType.steady => 'steady',
    };

WorkoutBlockType workoutBlockTypeFromString(String s) => switch (s) {
      'warmup' => WorkoutBlockType.warmup,
      'interval' => WorkoutBlockType.interval,
      'recovery' => WorkoutBlockType.recovery,
      'cooldown' => WorkoutBlockType.cooldown,
      _ => WorkoutBlockType.steady,
    };

final class WorkoutBlockEntity extends Equatable {
  final String id;
  final String templateId;
  final int orderIndex;
  final WorkoutBlockType blockType;
  final int? durationSeconds;
  final int? distanceMeters;
  final int? targetPaceSecondsPerKm;
  final int? targetHrZone;
  final int? rpeTarget;
  final String? notes;

  const WorkoutBlockEntity({
    required this.id,
    required this.templateId,
    required this.orderIndex,
    required this.blockType,
    this.durationSeconds,
    this.distanceMeters,
    this.targetPaceSecondsPerKm,
    this.targetHrZone,
    this.rpeTarget,
    this.notes,
  });

  @override
  List<Object?> get props => [id, templateId, orderIndex, blockType];
}

final class WorkoutTemplateEntity extends Equatable {
  final String id;
  final String groupId;
  final String name;
  final String? description;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkoutBlockEntity> blocks;

  const WorkoutTemplateEntity({
    required this.id,
    required this.groupId,
    required this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.blocks = const [],
  });

  @override
  List<Object?> get props => [id, groupId, name];
}
