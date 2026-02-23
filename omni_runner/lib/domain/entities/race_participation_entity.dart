import 'package:equatable/equatable.dart';

/// An athlete's participation record in a coaching race event.
///
/// Tracks accumulated progress toward the race target and ranking position.
/// The combination [raceEventId] + [userId] is unique — enforced by the repo.
///
/// Distinct from [EventParticipationEntity] (Phase 15 — Social virtual events).
/// Race participations are tied to a coaching group and presential races.
///
/// Immutable value object. See Phase 16 — Event Gamification Engine.
final class RaceParticipationEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String raceEventId;
  final String userId;

  /// Cached for offline display.
  final String displayName;

  /// When the athlete enrolled in the race (ms since epoch, UTC).
  final int joinedAtMs;

  /// Total accumulated distance in meters from contributing sessions.
  final double totalDistanceM;

  /// Total accumulated moving time in milliseconds.
  final int totalMovingMs;

  /// Best average pace in sec/km among contributing sessions.
  /// Null if no session with pace data has contributed.
  final double? bestPaceSecPerKm;

  /// Number of verified sessions that contributed to this participation.
  final int contributingSessionCount;

  /// IDs of sessions that already contributed (dedup guard).
  final List<String> contributingSessionIds;

  /// Whether the athlete reached the race's target.
  final bool completed;

  /// When the athlete completed the target (ms since epoch, UTC).
  /// Null if [completed] is false.
  final int? completedAtMs;

  /// Live ranking position within the race (1-indexed). Null if not computed.
  final int? rank;

  const RaceParticipationEntity({
    required this.id,
    required this.raceEventId,
    required this.userId,
    required this.displayName,
    required this.joinedAtMs,
    this.totalDistanceM = 0.0,
    this.totalMovingMs = 0,
    this.bestPaceSecPerKm,
    this.contributingSessionCount = 0,
    this.contributingSessionIds = const [],
    this.completed = false,
    this.completedAtMs,
    this.rank,
  });

  /// Progress as a fraction 0.0–1.0 given the race's [targetDistanceM].
  /// Returns 0.0 if [targetDistanceM] is null or zero (ranking-only races).
  double progressFraction(double? targetDistanceM) =>
      (targetDistanceM != null && targetDistanceM > 0)
          ? (totalDistanceM / targetDistanceM).clamp(0.0, 1.0)
          : 0.0;

  /// Whether the given session already contributed to this participation.
  bool hasSession(String sessionId) =>
      contributingSessionIds.contains(sessionId);

  RaceParticipationEntity copyWith({
    double? totalDistanceM,
    int? totalMovingMs,
    double? bestPaceSecPerKm,
    int? contributingSessionCount,
    List<String>? contributingSessionIds,
    bool? completed,
    int? completedAtMs,
    int? rank,
  }) =>
      RaceParticipationEntity(
        id: id,
        raceEventId: raceEventId,
        userId: userId,
        displayName: displayName,
        joinedAtMs: joinedAtMs,
        totalDistanceM: totalDistanceM ?? this.totalDistanceM,
        totalMovingMs: totalMovingMs ?? this.totalMovingMs,
        bestPaceSecPerKm: bestPaceSecPerKm ?? this.bestPaceSecPerKm,
        contributingSessionCount:
            contributingSessionCount ?? this.contributingSessionCount,
        contributingSessionIds:
            contributingSessionIds ?? this.contributingSessionIds,
        completed: completed ?? this.completed,
        completedAtMs: completedAtMs ?? this.completedAtMs,
        rank: rank ?? this.rank,
      );

  @override
  List<Object?> get props => [
        id,
        raceEventId,
        userId,
        displayName,
        joinedAtMs,
        totalDistanceM,
        totalMovingMs,
        bestPaceSecPerKm,
        contributingSessionCount,
        contributingSessionIds,
        completed,
        completedAtMs,
        rank,
      ];
}
