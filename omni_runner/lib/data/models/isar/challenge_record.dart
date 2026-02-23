import 'package:isar/isar.dart';

part 'challenge_record.g.dart';

/// Isar collection for persisting challenges.
///
/// Maps to/from [ChallengeEntity] in the domain layer.
///
/// Participants are stored as JSON-encoded strings because Isar 3.x
/// does not support nested object lists. Each participant is a JSON
/// object with keys: userId, displayName, status, respondedAtMs,
/// progressValue, contributingSessionIds.
///
/// Status int mapping (matches [ChallengeStatus] enum ordinal):
///   0 = pending, 1 = active, 2 = completing,
///   3 = completed, 4 = cancelled, 5 = expired
///
/// Type int mapping (matches [ChallengeType] enum ordinal):
///   0 = oneVsOne, 1 = group, 2 = teamVsTeam
@collection
class ChallengeRecord {
  Id isarId = Isar.autoIncrement;

  /// Application-level unique identifier (UUID v4).
  @Index(unique: true)
  late String challengeUuid;

  /// User ID of the challenge creator.
  @Index()
  late String creatorUserId;

  /// Lifecycle status as integer.
  @Index()
  late int status;

  /// Challenge type as integer.
  late int type;

  /// Human-readable title. Null if not set.
  String? title;

  // ── Rules (flattened) ──

  /// ChallengeMetric ordinal: 0=distance, 1=pace, 2=time.
  late int metricOrdinal;

  /// Target value. Null for open-ended challenges.
  double? target;

  /// Window duration in milliseconds.
  late int windowMs;

  /// ChallengeStartMode ordinal: 0=onAccept, 1=scheduled.
  late int startModeOrdinal;

  /// Fixed start timestamp for scheduled challenges.
  int? fixedStartMs;

  /// Minimum session distance in meters.
  late double minSessionDistanceM;

  /// ChallengeAntiCheatPolicy ordinal: 0=standard, 1=strict.
  late int antiCheatPolicyOrdinal;

  /// Entry fee in OmniCoins per participant. 0 = free challenge.
  late int entryFeeCoins;

  // ── Timestamps ──

  @Index()
  late int createdAtMs;

  int? startsAtMs;

  int? endsAtMs;

  // ── Team fields (teamVsTeam only) ──

  String? teamAGroupId;
  String? teamBGroupId;
  String? teamAGroupName;
  String? teamBGroupName;

  // ── Participants (JSON-encoded) ──

  /// Each element is a JSON string representing one participant.
  List<String> participantsJson = const [];
}
