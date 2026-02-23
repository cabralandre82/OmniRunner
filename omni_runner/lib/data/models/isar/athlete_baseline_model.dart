import 'package:isar/isar.dart';

part 'athlete_baseline_model.g.dart';

/// Isar collection for persisting athlete baseline snapshots.
///
/// Maps to/from [AthleteBaselineEntity] in the domain layer.
/// One record per (userId, groupId, metric) — upserted on recompute.
///
/// EvolutionMetric ordinal mapping (append-only — DECISAO 018):
///   0 = avgPace, 1 = avgDistance, 2 = weeklyVolume,
///   3 = weeklyFrequency, 4 = avgHeartRate, 5 = avgMovingTime
@collection
class AthleteBaselineRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String baselineUuid;

  @Index()
  late String userId;

  @Index()
  late String groupId;

  /// [EvolutionMetric] as integer ordinal.
  late int metricOrdinal;

  late double value;
  late int sampleSize;
  late int windowStartMs;
  late int windowEndMs;
  late int computedAtMs;
}
