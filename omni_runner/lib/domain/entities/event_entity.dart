import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/group_entity.dart';

/// Type of virtual running event.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum EventType {
  /// Each participant has a personal target.
  individual,

  /// Teams of N share a collective target.
  team,
}

/// Lifecycle status of an event.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum EventStatus {
  /// Created but start time not yet reached.
  upcoming,

  /// Currently accepting contributions.
  active,

  /// Ended — rewards distributed.
  completed,

  /// Cancelled before or during the event.
  cancelled,
}

/// Rewards granted for event participation and completion.
///
/// Immutable value object. All fields are non-negative.
/// Use [EventRewards.userCreated] for user-created events (enforces caps).
/// See `docs/SOCIAL_SPEC.md` §5.3.
final class EventRewards extends Equatable {
  static const int maxXpCompletion = 500;
  static const int maxCoinsCompletion = 200;
  static const int maxXpParticipation = 100;

  /// XP granted upon reaching [EventEntity.targetValue].
  final int xpCompletion;

  /// Coins granted upon reaching [EventEntity.targetValue].
  final int coinsCompletion;

  /// Minimum XP for participating (≥ 1 verified session during event).
  final int xpParticipation;

  /// Exclusive badge unlocked upon completion. Null if none.
  /// Only system-created events may set a badge.
  final String? badgeId;

  const EventRewards({
    this.xpCompletion = 0,
    this.coinsCompletion = 0,
    this.xpParticipation = 0,
    this.badgeId,
  });

  /// Factory for user-created events: clamps values to safe maximums
  /// and strips badgeId (only official events grant badges).
  factory EventRewards.userCreated({
    int xpCompletion = 0,
    int coinsCompletion = 0,
    int xpParticipation = 0,
  }) =>
      EventRewards(
        xpCompletion: xpCompletion.clamp(0, maxXpCompletion),
        coinsCompletion: coinsCompletion.clamp(0, maxCoinsCompletion),
        xpParticipation: xpParticipation.clamp(0, maxXpParticipation),
      );

  @override
  List<Object?> get props => [
        xpCompletion,
        coinsCompletion,
        xpParticipation,
        badgeId,
      ];
}

/// A virtual running event with a fixed period, goals, and rewards.
///
/// Events are either official (system-created, global, with exclusive badges)
/// or user-created (limited to friends/group, no badges).
///
/// Immutable value object. See `docs/SOCIAL_SPEC.md` §5.
final class EventEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  /// Display title (e.g. "Carnaval Run 2026").
  final String title;

  final String description;

  /// Banner image URL. Null if none.
  final String? imageUrl;

  final EventType type;

  /// Which metric contributions are measured in.
  /// Reuses [GoalMetric] from group_entity.dart.
  final GoalMetric metric;

  /// Individual target value (meters, count, or ms).
  /// Null if the event is ranking-only (no personal goal).
  final double? targetValue;

  /// When the event window opens (ms since epoch, UTC).
  final int startsAtMs;

  /// When the event window closes (ms since epoch, UTC).
  final int endsAtMs;

  /// Maximum participants. Null = unlimited.
  final int? maxParticipants;

  /// True for system/admin-created events; false for user-created.
  final bool createdBySystem;

  /// User who created the event. Null if [createdBySystem] is true.
  final String? creatorUserId;

  final EventRewards rewards;
  final EventStatus status;

  const EventEntity({
    required this.id,
    required this.title,
    this.description = '',
    this.imageUrl,
    required this.type,
    required this.metric,
    this.targetValue,
    required this.startsAtMs,
    required this.endsAtMs,
    this.maxParticipants,
    this.createdBySystem = false,
    this.creatorUserId,
    this.rewards = const EventRewards(),
    this.status = EventStatus.upcoming,
  });

  /// Duration of the event in milliseconds.
  int get durationMs => endsAtMs - startsAtMs;

  /// Whether the event window is currently open given [nowMs].
  bool isActive(int nowMs) =>
      status == EventStatus.active &&
      nowMs >= startsAtMs &&
      nowMs <= endsAtMs;

  /// Whether the event has ended given [nowMs].
  bool hasEnded(int nowMs) => nowMs > endsAtMs;

  /// Whether this is a ranking-only event (no individual target).
  bool get isRankingOnly => targetValue == null;

  EventEntity copyWith({
    EventStatus? status,
  }) =>
      EventEntity(
        id: id,
        title: title,
        description: description,
        imageUrl: imageUrl,
        type: type,
        metric: metric,
        targetValue: targetValue,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        maxParticipants: maxParticipants,
        createdBySystem: createdBySystem,
        creatorUserId: creatorUserId,
        rewards: rewards,
        status: status ?? this.status,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        imageUrl,
        type,
        metric,
        targetValue,
        startsAtMs,
        endsAtMs,
        maxParticipants,
        createdBySystem,
        creatorUserId,
        rewards,
        status,
      ];
}
