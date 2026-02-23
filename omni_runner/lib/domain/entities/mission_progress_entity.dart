import 'package:equatable/equatable.dart';

/// Lifecycle of a user's assigned mission.
enum MissionProgressStatus {
  /// Assigned and active — user can make progress.
  active,

  /// All criteria met — rewards pending or already credited.
  completed,

  /// Deadline passed without completion — no penalty.
  expired,
}

/// Tracks a specific user's progress toward completing a mission.
///
/// Each [MissionProgressEntity] maps 1:1 to a [MissionEntity]
/// assigned to the user. Progress is updated after each verified
/// session by the `CheckMissionProgress` use case.
///
/// Immutable value object — mutations produce new instances via [copyWith].
/// See `docs/PROGRESSION_SPEC.md` §7.
final class MissionProgressEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String userId;

  /// References [MissionEntity.id].
  final String missionId;

  final MissionProgressStatus status;

  /// Numeric progress toward the goal.
  ///
  /// Interpretation depends on [MissionCriteria]:
  /// - [AccumulateDistance]: meters accumulated so far
  /// - [CompleteSessionCount]: sessions completed so far
  /// - [AchievePaceTarget]: 1.0 if achieved, 0.0 otherwise
  /// - [SingleSessionDurationTarget]: 1.0 if achieved, 0.0 otherwise
  /// - [HrZoneTime]: ms spent in target zone so far
  /// - [MaintainStreak]: current streak days
  /// - [CompleteChallenges]: challenges completed so far
  final double currentValue;

  /// Target value derived from the [MissionCriteria].
  /// Used for progress percentage: `currentValue / targetValue`.
  final double targetValue;

  /// When the mission was assigned to the user (ms epoch UTC).
  final int assignedAtMs;

  /// When the mission was completed (ms epoch UTC). Null if not yet.
  final int? completedAtMs;

  /// How many times this user has completed this mission.
  /// Relevant for repeatable missions.
  final int completionCount;

  /// IDs of sessions that contributed to this mission's progress.
  final List<String> contributingSessionIds;

  const MissionProgressEntity({
    required this.id,
    required this.userId,
    required this.missionId,
    this.status = MissionProgressStatus.active,
    this.currentValue = 0.0,
    required this.targetValue,
    required this.assignedAtMs,
    this.completedAtMs,
    this.completionCount = 0,
    this.contributingSessionIds = const [],
  });

  /// Progress as a 0.0–1.0 fraction, clamped.
  double get progressFraction =>
      targetValue > 0 ? (currentValue / targetValue).clamp(0.0, 1.0) : 0.0;

  /// Whether the criteria has been met (regardless of [status]).
  bool get isCriteriaMet => currentValue >= targetValue;

  MissionProgressEntity copyWith({
    MissionProgressStatus? status,
    double? currentValue,
    int? completedAtMs,
    int? completionCount,
    List<String>? contributingSessionIds,
  }) =>
      MissionProgressEntity(
        id: id,
        userId: userId,
        missionId: missionId,
        status: status ?? this.status,
        currentValue: currentValue ?? this.currentValue,
        targetValue: targetValue,
        assignedAtMs: assignedAtMs,
        completedAtMs: completedAtMs ?? this.completedAtMs,
        completionCount: completionCount ?? this.completionCount,
        contributingSessionIds:
            contributingSessionIds ?? this.contributingSessionIds,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        missionId,
        status,
        currentValue,
        targetValue,
        assignedAtMs,
        completedAtMs,
        completionCount,
        contributingSessionIds,
      ];
}
