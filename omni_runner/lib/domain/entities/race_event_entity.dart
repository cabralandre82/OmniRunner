import 'package:equatable/equatable.dart';

/// Metric used to measure progress in a coaching race event.
///
/// Distinct from [GoalMetric] (Social) and [CoachingRankingMetric] (Ranking).
/// Focused on real-world race measurement: distance, time, and pace.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum RaceEventMetric {
  /// Total accumulated distance in meters.
  distance,

  /// Total moving time in milliseconds.
  time,

  /// Best average pace in sec/km (lower is better).
  pace,
}

/// Lifecycle status of a coaching race event.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum RaceEventStatus {
  /// Created but event date not yet reached.
  upcoming,

  /// Currently accepting session contributions.
  active,

  /// Ended — results computed and rewards distributed.
  completed,

  /// Cancelled by the coach before or during the event.
  cancelled,
}

/// A real-world race or coaching event tied to a coaching group.
///
/// Unlike [EventEntity] (Social & Events, Phase 15), race events represent
/// **presential** races (e.g. 10K, half marathon) that the coach creates
/// for their group. Athletes link verified sessions to the event.
///
/// Gamification rewards (XP + Coins) are granted upon event completion.
/// Reward caps follow [EventRewards] conventions from `GAMIFICATION_POLICY.md`.
///
/// Immutable value object. See Phase 16 — Event Gamification Engine.
final class RaceEventEntity extends Equatable {
  static const int maxXpReward = 500;
  static const int maxCoinsReward = 200;

  /// Unique identifier (UUID v4).
  final String id;

  /// Coaching group that owns this event.
  final String groupId;

  /// Display title (e.g. "Meia Maratona de São Paulo 2026").
  final String title;

  final String description;

  /// Physical location (city or venue name). Empty if not specified.
  final String location;

  /// Primary metric for ranking participants.
  final RaceEventMetric metric;

  /// Target distance in meters for completion (e.g. 10000 for 10K).
  /// Null if the event is ranking-only (no individual target).
  final double? targetDistanceM;

  /// When the event window opens (ms since epoch, UTC).
  final int startsAtMs;

  /// When the event window closes (ms since epoch, UTC).
  final int endsAtMs;

  final RaceEventStatus status;

  /// Maximum participants. Null = unlimited.
  final int? maxParticipants;

  /// Coach/assistant who created the event.
  final String createdByUserId;

  /// When the event was created (ms since epoch, UTC).
  final int createdAtMs;

  /// XP granted to athletes who complete the target. Capped at [maxXpReward].
  final int xpReward;

  /// Coins granted to athletes who complete the target. Capped at [maxCoinsReward].
  final int coinsReward;

  /// Optional badge ID unlocked upon completion. Null if none.
  final String? badgeId;

  const RaceEventEntity({
    required this.id,
    required this.groupId,
    required this.title,
    this.description = '',
    this.location = '',
    required this.metric,
    this.targetDistanceM,
    required this.startsAtMs,
    required this.endsAtMs,
    this.status = RaceEventStatus.upcoming,
    this.maxParticipants,
    required this.createdByUserId,
    required this.createdAtMs,
    this.xpReward = 0,
    this.coinsReward = 0,
    this.badgeId,
  });

  /// Factory that clamps rewards to safe maximums.
  factory RaceEventEntity.withCappedRewards({
    required String id,
    required String groupId,
    required String title,
    String description = '',
    String location = '',
    required RaceEventMetric metric,
    double? targetDistanceM,
    required int startsAtMs,
    required int endsAtMs,
    RaceEventStatus status = RaceEventStatus.upcoming,
    int? maxParticipants,
    required String createdByUserId,
    required int createdAtMs,
    int xpReward = 0,
    int coinsReward = 0,
    String? badgeId,
  }) =>
      RaceEventEntity(
        id: id,
        groupId: groupId,
        title: title,
        description: description,
        location: location,
        metric: metric,
        targetDistanceM: targetDistanceM,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        status: status,
        maxParticipants: maxParticipants,
        createdByUserId: createdByUserId,
        createdAtMs: createdAtMs,
        xpReward: xpReward.clamp(0, maxXpReward),
        coinsReward: coinsReward.clamp(0, maxCoinsReward),
        badgeId: badgeId,
      );

  /// Duration of the event in milliseconds.
  int get durationMs => endsAtMs - startsAtMs;

  /// Whether the event window is currently open.
  bool isActive(int nowMs) =>
      status == RaceEventStatus.active &&
      nowMs >= startsAtMs &&
      nowMs <= endsAtMs;

  /// Whether the event has ended.
  bool hasEnded(int nowMs) => nowMs > endsAtMs;

  /// Whether this is a ranking-only event (no distance target).
  bool get isRankingOnly => targetDistanceM == null;

  RaceEventEntity copyWith({
    RaceEventStatus? status,
  }) =>
      RaceEventEntity(
        id: id,
        groupId: groupId,
        title: title,
        description: description,
        location: location,
        metric: metric,
        targetDistanceM: targetDistanceM,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        status: status ?? this.status,
        maxParticipants: maxParticipants,
        createdByUserId: createdByUserId,
        createdAtMs: createdAtMs,
        xpReward: xpReward,
        coinsReward: coinsReward,
        badgeId: badgeId,
      );

  @override
  List<Object?> get props => [
        id,
        groupId,
        title,
        description,
        location,
        metric,
        targetDistanceM,
        startsAtMs,
        endsAtMs,
        status,
        maxParticipants,
        createdByUserId,
        createdAtMs,
        xpReward,
        coinsReward,
        badgeId,
      ];
}
