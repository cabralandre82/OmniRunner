import 'package:equatable/equatable.dart';

/// A user's participation record in a virtual event.
///
/// Tracks progress toward the event target and ranking position.
/// The combination of [eventId] + [userId] is unique — enforced by the repo.
///
/// Immutable value object. See `docs/SOCIAL_SPEC.md` §5.1.
final class EventParticipationEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String eventId;
  final String userId;

  /// Cached for offline display.
  final String displayName;

  /// When the user joined the event (ms since epoch, UTC).
  final int joinedAtMs;

  /// Accumulated progress value (meters, session count, or ms).
  final double currentValue;

  /// Live ranking position within the event (1-indexed). Null if not computed.
  final int? rank;

  /// Whether the user reached the event's [EventEntity.targetValue].
  final bool completed;

  /// When the user completed the target (ms since epoch, UTC).
  /// Null if [completed] is false.
  final int? completedAtMs;

  /// Number of verified sessions that contributed to this event.
  final int contributingSessionCount;

  /// IDs of sessions that already contributed (dedup guard).
  final List<String> contributingSessionIds;

  /// Whether rewards have been claimed for this participation.
  final bool rewardsClaimed;

  const EventParticipationEntity({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.displayName,
    required this.joinedAtMs,
    this.currentValue = 0.0,
    this.rank,
    this.completed = false,
    this.completedAtMs,
    this.contributingSessionCount = 0,
    this.contributingSessionIds = const [],
    this.rewardsClaimed = false,
  });

  /// Progress as a fraction 0.0–1.0 given the event's [targetValue].
  /// Returns 0.0 if [targetValue] is null or zero (ranking-only events).
  double progressFraction(double? targetValue) =>
      (targetValue != null && targetValue > 0)
          ? (currentValue / targetValue).clamp(0.0, 1.0)
          : 0.0;

  /// Whether the given session already contributed to this participation.
  bool hasSession(String sessionId) => contributingSessionIds.contains(sessionId);

  EventParticipationEntity copyWith({
    double? currentValue,
    int? rank,
    bool? completed,
    int? completedAtMs,
    int? contributingSessionCount,
    List<String>? contributingSessionIds,
    bool? rewardsClaimed,
  }) =>
      EventParticipationEntity(
        id: id,
        eventId: eventId,
        userId: userId,
        displayName: displayName,
        joinedAtMs: joinedAtMs,
        currentValue: currentValue ?? this.currentValue,
        rank: rank ?? this.rank,
        completed: completed ?? this.completed,
        completedAtMs: completedAtMs ?? this.completedAtMs,
        contributingSessionCount:
            contributingSessionCount ?? this.contributingSessionCount,
        contributingSessionIds:
            contributingSessionIds ?? this.contributingSessionIds,
        rewardsClaimed: rewardsClaimed ?? this.rewardsClaimed,
      );

  @override
  List<Object?> get props => [
        id,
        eventId,
        userId,
        displayName,
        joinedAtMs,
        currentValue,
        rank,
        completed,
        completedAtMs,
        contributingSessionCount,
        contributingSessionIds,
        rewardsClaimed,
      ];
}
