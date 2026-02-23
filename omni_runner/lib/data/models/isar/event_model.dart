import 'package:isar/isar.dart';

part 'event_model.g.dart';

/// Isar collection for persisting virtual running events.
///
/// Maps to/from [EventEntity] in the domain layer.
///
/// EventType ordinal mapping (append-only — DECISAO 018):
///   0 = individual, 1 = team
///
/// EventStatus ordinal mapping (append-only — DECISAO 018):
///   0 = upcoming, 1 = active, 2 = completed, 3 = cancelled
///
/// GoalMetric ordinal mapping (shared with GroupGoalRecord):
///   0 = distance, 1 = sessions, 2 = movingTime
@collection
class EventRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String eventUuid;

  late String title;
  late String description;
  String? imageUrl;

  /// [EventType] as integer ordinal.
  late int typeOrdinal;

  /// [GoalMetric] as integer ordinal.
  late int metricOrdinal;

  /// Individual target. Null if ranking-only event.
  double? targetValue;

  late int startsAtMs;
  late int endsAtMs;

  /// Null = unlimited.
  int? maxParticipants;

  late bool createdBySystem;

  /// Null if [createdBySystem] is true.
  String? creatorUserId;

  // ── Rewards (flattened) ──

  late int rewardXpCompletion;
  late int rewardCoinsCompletion;
  late int rewardXpParticipation;
  String? rewardBadgeId;

  /// [EventStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;
}

/// Isar collection for event participation records.
///
/// Maps to/from [EventParticipationEntity] in the domain layer.
/// Combination (eventId, userId) is unique — enforced by composite index.
@collection
class EventParticipationRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String participationUuid;

  @Index(unique: true, composite: [CompositeIndex('userId')])
  late String eventId;

  @Index()
  late String userId;

  late String displayName;

  late int joinedAtMs;
  late double currentValue;

  /// Null if not ranked yet.
  int? rank;

  late bool completed;
  int? completedAtMs;

  late int contributingSessionCount;

  /// Session IDs that contributed, serialized as CSV.
  late String contributingSessionIdsCsv;

  late bool rewardsClaimed;
}
