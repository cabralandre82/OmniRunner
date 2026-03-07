// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'season_model.g.dart';

/// Isar collection for season metadata.
///
/// Maps to/from [SeasonEntity].
///
/// SeasonStatus ordinal mapping:
///   0 = upcoming, 1 = active, 2 = settling, 3 = completed
@collection
class SeasonRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String seasonUuid;

  late String name;

  @Index()
  late int statusOrdinal;

  late int startsAtMs;
  late int endsAtMs;

  /// Pass milestones as comma-separated ints (e.g. "200,500,1000,...").
  late String passXpMilestonesStr;
}

/// Isar collection for per-user season progress.
///
/// Maps to/from [SeasonProgressEntity].
/// Unique per (userId, seasonId).
@collection
class SeasonProgressRecord {
  Id isarId = Isar.autoIncrement;

  @Index()
  late String userId;

  @Index()
  late String seasonId;

  late int seasonXp;

  /// Claimed milestone indices as comma-separated ints (e.g. "0,1,2").
  /// Empty string if none claimed.
  late String claimedMilestoneIndicesStr;

  late bool endRewardsClaimed;
}
