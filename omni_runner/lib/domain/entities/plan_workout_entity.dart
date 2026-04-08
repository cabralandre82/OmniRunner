import 'package:equatable/equatable.dart';

/// Status do ciclo de vida de um treino prescrito.
enum PlanWorkoutStatus {
  draft,
  scheduled,
  released,
  inProgress,
  completed,
  cancelled,
  replaced,
  archived;

  static PlanWorkoutStatus fromString(String value) => switch (value) {
        'draft'       => draft,
        'scheduled'   => scheduled,
        'released'    => released,
        'in_progress' => inProgress,
        'completed'   => completed,
        'cancelled'   => cancelled,
        'replaced'    => replaced,
        'archived'    => archived,
        _             => draft,
      };

  String get label => switch (this) {
        draft       => 'Rascunho',
        scheduled   => 'Agendado',
        released    => 'Liberado',
        inProgress  => 'Em andamento',
        completed   => 'Concluído',
        cancelled   => 'Cancelado',
        replaced    => 'Substituído',
        archived    => 'Arquivado',
      };

  bool get isVisibleToAthlete =>
      this == released ||
      this == inProgress ||
      this == completed ||
      this == cancelled ||
      this == replaced;

  bool get isActionable => this == released || this == inProgress;
}

/// Bloco do treino prescrito (do content_snapshot).
class PlanWorkoutBlock extends Equatable {
  const PlanWorkoutBlock({
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

  final int orderIndex;
  final String blockType;
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

  factory PlanWorkoutBlock.fromJson(Map<String, dynamic> json) => PlanWorkoutBlock(
        orderIndex:            (json['order_index'] as num?)?.toInt() ?? 0,
        blockType:             (json['block_type'] as String?) ?? 'steady',
        durationSeconds:       (json['duration_seconds'] as num?)?.toInt(),
        distanceMeters:        (json['distance_meters'] as num?)?.toInt(),
        targetPaceMinSecPerKm: (json['target_pace_min_sec_per_km'] as num?)?.toInt(),
        targetPaceMaxSecPerKm: (json['target_pace_max_sec_per_km'] as num?)?.toInt(),
        targetHrZone:          (json['target_hr_zone'] as num?)?.toInt(),
        targetHrMin:           (json['target_hr_min'] as num?)?.toInt(),
        targetHrMax:           (json['target_hr_max'] as num?)?.toInt(),
        rpeTarget:             (json['rpe_target'] as num?)?.toInt(),
        repeatCount:           (json['repeat_count'] as num?)?.toInt(),
        notes:                 json['notes'] as String?,
      );

  String get blockTypeLabel => switch (blockType) {
        'warmup'   => 'Aquecimento',
        'interval' => 'Intervalo',
        'recovery' => 'Recuperação',
        'cooldown' => 'Resfriamento',
        'steady'   => 'Ritmo contínuo',
        'rest'     => 'Descanso',
        'repeat'   => 'Repetição',
        _          => blockType,
      };

  /// Formata pace em min:sec/km
  static String formatPace(int secondsPerKm) {
    final min = secondsPerKm ~/ 60;
    final sec = secondsPerKm % 60;
    return '$min:${sec.toString().padLeft(2, '0')}/km';
  }

  @override
  List<Object?> get props => [
        orderIndex, blockType, durationSeconds, distanceMeters,
        targetPaceMinSecPerKm, targetPaceMaxSecPerKm,
        targetHrZone, targetHrMin, targetHrMax, rpeTarget, repeatCount, notes,
      ];
}

/// Snapshot do conteúdo do treino prescrito (template + blocos).
class WorkoutContentSnapshot extends Equatable {
  const WorkoutContentSnapshot({
    this.templateId,
    required this.templateName,
    this.description,
    required this.blocks,
    this.snapshotAt,
  });

  final String? templateId;
  final String templateName;
  final String? description;
  final List<PlanWorkoutBlock> blocks;
  final DateTime? snapshotAt;

  double get totalDistanceM => blocks
      .where((b) => b.blockType != 'rest' && b.distanceMeters != null)
      .fold(0.0, (sum, b) => sum + (b.distanceMeters ?? 0));

  factory WorkoutContentSnapshot.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'] as List<dynamic>? ?? [];
    return WorkoutContentSnapshot(
      templateId:   json['template_id'] as String?,
      templateName: (json['template_name'] as String?) ?? 'Treino',
      description:  json['description'] as String?,
      blocks:       rawBlocks
          .map((b) => PlanWorkoutBlock.fromJson(b as Map<String, dynamic>))
          .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
      snapshotAt:   json['snapshot_at'] != null
          ? DateTime.tryParse(json['snapshot_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [templateId, templateName, description, blocks, snapshotAt];
}

/// Execução real do treino pelo atleta.
class CompletedWorkoutSummary extends Equatable {
  const CompletedWorkoutSummary({
    required this.id,
    this.actualDistanceM,
    this.actualDurationS,
    this.actualAvgPaceSKm,
    this.actualAvgHr,
    this.perceivedEffort,
    this.finishedAt,
  });

  final String id;
  final double? actualDistanceM;
  final int? actualDurationS;
  final double? actualAvgPaceSKm;
  final double? actualAvgHr;
  final int? perceivedEffort;
  final DateTime? finishedAt;

  factory CompletedWorkoutSummary.fromJson(Map<String, dynamic> json) =>
      CompletedWorkoutSummary(
        id:                (json['id'] as String?) ?? '',
        actualDistanceM:   (json['actual_distance_m'] as num?)?.toDouble(),
        actualDurationS:   (json['actual_duration_s'] as num?)?.toInt(),
        actualAvgPaceSKm:  (json['actual_avg_pace_s_km'] as num?)?.toDouble(),
        actualAvgHr:       (json['actual_avg_hr'] as num?)?.toDouble(),
        perceivedEffort:   (json['perceived_effort'] as num?)?.toInt(),
        finishedAt:        json['finished_at'] != null
            ? DateTime.tryParse(json['finished_at'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, actualDistanceM, actualDurationS, finishedAt];
}

/// Feedback do atleta sobre o treino.
class WorkoutFeedbackSummary extends Equatable {
  const WorkoutFeedbackSummary({
    this.rating,
    this.mood,
    this.howWasIt,
  });

  final int? rating;
  final int? mood;
  final String? howWasIt;

  factory WorkoutFeedbackSummary.fromJson(Map<String, dynamic> json) =>
      WorkoutFeedbackSummary(
        rating:    (json['rating'] as num?)?.toInt(),
        mood:      (json['mood'] as num?)?.toInt(),
        howWasIt:  json['how_was_it'] as String?,
      );

  @override
  List<Object?> get props => [rating, mood, howWasIt];
}

/// Entidade principal: treino prescrito e seu estado completo.
class PlanWorkoutEntity extends Equatable {
  const PlanWorkoutEntity({
    required this.id,
    required this.scheduledDate,
    required this.workoutOrder,
    required this.status,
    required this.workoutType,
    this.workoutLabel,
    this.coachNotes,
    required this.contentVersion,
    this.contentSnapshot,
    this.releasedAt,
    this.cancelledAt,
    this.replacedById,
    required this.updatedAt,
    this.completedWorkout,
    this.feedback,
  });

  final String id;
  final DateTime scheduledDate;
  final int workoutOrder;
  final PlanWorkoutStatus status;
  final String workoutType;
  final String? workoutLabel;
  final String? coachNotes;
  final int contentVersion;
  final WorkoutContentSnapshot? contentSnapshot;
  final DateTime? releasedAt;
  final DateTime? cancelledAt;
  final String? replacedById;
  final DateTime updatedAt;
  final CompletedWorkoutSummary? completedWorkout;
  final WorkoutFeedbackSummary? feedback;

  String get displayName =>
      workoutLabel ?? contentSnapshot?.templateName ?? 'Treino';

  bool get isUpdatedAfterSync => contentVersion > 1;

  bool get hasCompletion => completedWorkout != null;

  factory PlanWorkoutEntity.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['content_snapshot'];
    final rawCompleted = json['completed_workout'];
    final rawFeedback = json['feedback'];

    return PlanWorkoutEntity(
      id:             (json['id'] as String?) ?? '',
      scheduledDate:  DateTime.parse((json['scheduled_date'] as String?) ?? '1970-01-01'),
      workoutOrder:   (json['workout_order'] as num?)?.toInt() ?? 1,
      status:         PlanWorkoutStatus.fromString((json['release_status'] as String?) ?? 'draft'),
      workoutType:    (json['workout_type'] as String?) ?? 'continuous',
      workoutLabel:   json['workout_label'] as String?,
      coachNotes:     json['coach_notes'] as String?,
      contentVersion: (json['content_version'] as num?)?.toInt() ?? 1,
      contentSnapshot: rawSnapshot is Map<String, dynamic>
          ? WorkoutContentSnapshot.fromJson(rawSnapshot)
          : null,
      releasedAt:  json['released_at'] != null
          ? DateTime.tryParse(json['released_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'] as String)
          : null,
      replacedById: json['replaced_by_id'] as String?,
      updatedAt:   DateTime.parse((json['updated_at'] as String?) ?? '1970-01-01T00:00:00Z'),
      completedWorkout: rawCompleted is Map<String, dynamic>
          ? CompletedWorkoutSummary.fromJson(rawCompleted)
          : null,
      feedback: rawFeedback is Map<String, dynamic>
          ? WorkoutFeedbackSummary.fromJson(rawFeedback)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, scheduledDate, workoutOrder, status, contentVersion, updatedAt];
}
