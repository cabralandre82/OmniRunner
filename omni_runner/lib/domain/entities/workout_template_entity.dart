import 'package:equatable/equatable.dart';

enum WorkoutBlockType { warmup, interval, recovery, cooldown, steady, rest, repeat }

String workoutBlockTypeToString(WorkoutBlockType t) => switch (t) {
      WorkoutBlockType.warmup => 'warmup',
      WorkoutBlockType.interval => 'interval',
      WorkoutBlockType.recovery => 'recovery',
      WorkoutBlockType.cooldown => 'cooldown',
      WorkoutBlockType.steady => 'steady',
      WorkoutBlockType.rest => 'rest',
      WorkoutBlockType.repeat => 'repeat',
    };

WorkoutBlockType workoutBlockTypeFromString(String s) => switch (s) {
      'warmup' => WorkoutBlockType.warmup,
      'interval' => WorkoutBlockType.interval,
      'recovery' => WorkoutBlockType.recovery,
      'cooldown' => WorkoutBlockType.cooldown,
      'rest' => WorkoutBlockType.rest,
      'repeat' => WorkoutBlockType.repeat,
      _ => WorkoutBlockType.steady,
    };

String workoutBlockTypeLabel(WorkoutBlockType t) => switch (t) {
      WorkoutBlockType.warmup => 'Aquecimento',
      WorkoutBlockType.interval => 'Intervalo',
      WorkoutBlockType.recovery => 'Recuperação',
      WorkoutBlockType.cooldown => 'Desaquecimento',
      WorkoutBlockType.steady => 'Contínuo',
      WorkoutBlockType.rest => 'Descanso',
      WorkoutBlockType.repeat => 'Repetir',
    };

final class WorkoutBlockEntity extends Equatable {
  final String id;
  final String templateId;
  final int orderIndex;
  final WorkoutBlockType blockType;
  final int? durationSeconds;
  final int? distanceMeters;
  final int? targetPaceMinSecPerKm;
  final int? targetPaceMaxSecPerKm;
  final int? targetHrZone;
  final int? targetHrMin;
  final int? targetHrMax;
  final int? rpeTarget;
  final int? repeatCount;
  final String? notes;

  const WorkoutBlockEntity({
    required this.id,
    required this.templateId,
    required this.orderIndex,
    required this.blockType,
    this.durationSeconds,
    this.distanceMeters,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
    this.targetHrZone,
    this.targetHrMin,
    this.targetHrMax,
    this.rpeTarget,
    this.repeatCount,
    this.notes,
  });

  bool get isOpen => durationSeconds == null && distanceMeters == null;

  bool get hasPaceRange =>
      targetPaceMinSecPerKm != null && targetPaceMaxSecPerKm != null;

  bool get hasHrRange => targetHrMin != null && targetHrMax != null;

  int get totalDistanceMeters {
    if (blockType == WorkoutBlockType.repeat) return 0;
    return distanceMeters ?? 0;
  }

  @override
  List<Object?> get props => [
        id, templateId, orderIndex, blockType, durationSeconds, distanceMeters,
        targetPaceMinSecPerKm, targetPaceMaxSecPerKm, targetHrZone,
        targetHrMin, targetHrMax, rpeTarget, repeatCount,
      ];
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
