// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'coach_insight_model.g.dart';

/// Isar collection for persisting coach insights.
///
/// Maps to/from [CoachInsightEntity] in the domain layer.
/// One record per insight UUID — upserted on save/update.
///
/// InsightType ordinal mapping (append-only — DECISAO 018):
///   0 = performanceDecline, 1 = performanceImprovement,
///   2 = consistencyDrop, 3 = inactivityWarning,
///   4 = personalRecord, 5 = overtrainingRisk,
///   6 = raceReady, 7 = groupTrendSummary,
///   8 = eventMilestone, 9 = rankingChange
///
/// InsightPriority ordinal mapping (append-only — DECISAO 018):
///   0 = low, 1 = medium, 2 = high, 3 = critical
///
/// EvolutionMetric ordinal mapping (append-only — DECISAO 018):
///   0 = avgPace, 1 = avgDistance, 2 = weeklyVolume,
///   3 = weeklyFrequency, 4 = avgHeartRate, 5 = avgMovingTime
///   -1 = null (not applicable)
///
/// Nullable sentinel values:
///   String  → '' (empty)
///   int     → -1
///   double  → double.nan
@collection
class CoachInsightRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String insightUuid;

  @Index()
  late String groupId;

  /// Empty string for group-wide insights (no specific athlete).
  @Index()
  late String targetUserId;

  late String targetDisplayName;

  /// [InsightType] as integer ordinal.
  @Index()
  late int typeOrdinal;

  /// [InsightPriority] as integer ordinal.
  @Index()
  late int priorityOrdinal;

  late String title;
  late String message;

  /// [EvolutionMetric] as integer ordinal. -1 if not applicable.
  late int metricOrdinal;

  /// Sentinel: `double.nan` means null.
  late double referenceValue;

  /// Sentinel: `double.nan` means null.
  late double changePercent;

  /// Empty string if no related entity.
  late String relatedEntityId;

  late int createdAtMs;

  /// Sentinel: -1 means unread (null in entity).
  @Index()
  late int readAtMs;

  late bool dismissed;
}
