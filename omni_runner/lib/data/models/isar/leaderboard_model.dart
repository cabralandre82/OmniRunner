// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'leaderboard_model.g.dart';

/// Isar collection for leaderboard snapshots.
///
/// Maps to/from [LeaderboardEntity] in the domain layer.
/// Each snapshot represents a frozen state of a leaderboard for a period.
///
/// LeaderboardScope ordinal mapping (append-only — DECISAO 018):
///   0 = global, 1 = friends, 2 = group, 3 = season
///
/// LeaderboardPeriod ordinal mapping (append-only — DECISAO 018):
///   0 = weekly, 1 = monthly, 2 = season
///
/// LeaderboardMetric ordinal mapping (append-only — DECISAO 018):
///   0 = distance, 1 = sessions, 2 = movingTime, 3 = avgPace, 4 = seasonXp
@collection
class LeaderboardSnapshotRecord {
  Id isarId = Isar.autoIncrement;

  /// Composite key: scope + metric + periodKey (+ groupId if applicable).
  @Index(unique: true)
  late String snapshotUuid;

  /// [LeaderboardScope] as integer ordinal.
  late int scopeOrdinal;

  /// For [LeaderboardScope.group], the group ID. Null otherwise.
  String? groupId;

  /// [LeaderboardPeriod] as integer ordinal.
  late int periodOrdinal;

  /// [LeaderboardMetric] as integer ordinal.
  late int metricOrdinal;

  /// Human-readable period key, e.g. "2026-W08" or "2026-02".
  @Index()
  late String periodKey;

  late int computedAtMs;

  /// Whether this is the final immutable snapshot for a closed period.
  late bool isFinal;
}

/// Isar collection for individual leaderboard entries.
///
/// Maps to/from [LeaderboardEntryEntity] in the domain layer.
/// Linked to a [LeaderboardSnapshotRecord] via [snapshotId].
@collection
class LeaderboardEntryRecord {
  Id isarId = Isar.autoIncrement;

  /// References [LeaderboardSnapshotRecord.snapshotUuid].
  @Index()
  late String snapshotId;

  @Index()
  late String userId;

  late String displayName;
  String? avatarUrl;
  late int level;

  /// Metric value (meters, count, ms, sec/km, or XP).
  late double value;

  /// 1-indexed rank. Ties share rank; next rank skips.
  late int rank;

  late String periodKey;
}
