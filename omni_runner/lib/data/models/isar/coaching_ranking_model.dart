// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'coaching_ranking_model.g.dart';

/// Isar collection for coaching group ranking snapshots.
///
/// Maps to/from [CoachingGroupRankingEntity] in the domain layer.
/// Entries are stored in a separate collection ([CoachingRankingEntryRecord])
/// linked via [rankingUuid].
///
/// CoachingRankingMetric ordinal mapping (append-only — DECISAO 018):
///   0 = volumeDistance, 1 = totalTime, 2 = bestPace, 3 = consistencyDays
///
/// CoachingRankingPeriod ordinal mapping (append-only — DECISAO 018):
///   0 = weekly, 1 = monthly, 2 = custom
@collection
class CoachingRankingRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String rankingUuid;

  @Index()
  late String groupId;

  /// [CoachingRankingMetric] as integer ordinal.
  late int metricOrdinal;

  /// [CoachingRankingPeriod] as integer ordinal.
  late int periodOrdinal;

  /// Human-readable period key, e.g. "2026-W08" or "2026-02".
  @Index()
  late String periodKey;

  late int startsAtMs;
  late int endsAtMs;
  late int computedAtMs;
}
