import 'package:isar/isar.dart';

part 'coaching_ranking_entry_model.g.dart';

/// Isar collection for individual coaching ranking entries.
///
/// Maps to/from [CoachingRankingEntryEntity] in the domain layer.
/// Linked to a [CoachingRankingRecord] via [rankingId].
@collection
class CoachingRankingEntryRecord {
  Id isarId = Isar.autoIncrement;

  /// References [CoachingRankingRecord.rankingUuid].
  @Index()
  late String rankingId;

  @Index()
  late String userId;

  late String displayName;

  /// Metric value (meters, ms, sec/km, or day count).
  late double value;

  /// 1-indexed rank. Ties share rank; next rank skips.
  late int rank;

  /// Number of verified sessions contributing to [value].
  late int sessionCount;
}
