import 'package:isar/isar.dart';

part 'athlete_trend_model.g.dart';

/// Isar collection for persisting athlete trend analysis results.
///
/// Maps to/from [AthleteTrendEntity] in the domain layer.
/// One record per (userId, groupId, metric, period) — upserted on recompute.
///
/// EvolutionMetric ordinal mapping (append-only — DECISAO 018):
///   0 = avgPace, 1 = avgDistance, 2 = weeklyVolume,
///   3 = weeklyFrequency, 4 = avgHeartRate, 5 = avgMovingTime
///
/// EvolutionPeriod ordinal mapping (append-only — DECISAO 018):
///   0 = weekly, 1 = monthly
///
/// TrendDirection ordinal mapping (append-only — DECISAO 018):
///   0 = improving, 1 = stable, 2 = declining, 3 = insufficient
@collection
class AthleteTrendRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String trendUuid;

  @Index()
  late String userId;

  @Index()
  late String groupId;

  /// [EvolutionMetric] as integer ordinal.
  late int metricOrdinal;

  /// [EvolutionPeriod] as integer ordinal.
  late int periodOrdinal;

  /// [TrendDirection] as integer ordinal.
  @Index()
  late int directionOrdinal;

  late double currentValue;
  late double baselineValue;
  late double changePercent;
  late int dataPoints;
  late String latestPeriodKey;
  late int analyzedAtMs;
}
