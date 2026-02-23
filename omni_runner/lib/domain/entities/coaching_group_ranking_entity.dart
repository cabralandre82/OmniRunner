import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';

/// Period that a coaching ranking covers.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum CoachingRankingPeriod {
  /// Monday 00:00 UTC → Sunday 23:59 UTC.
  weekly,

  /// 1st of month 00:00 UTC → last day 23:59 UTC.
  monthly,

  /// Full custom range (e.g. training cycle defined by coach).
  custom,
}

/// A snapshot of a coaching group ranking for a specific metric and period.
///
/// Scoped to a single [CoachingGroupEntity] — each group has independent
/// rankings. The coach (or assistant) decides which metrics to display.
///
/// Immutable value object. See Phase 16 — Assessoria Mode § Ranking Engine.
final class CoachingGroupRankingEntity extends Equatable {
  /// Unique identifier (UUID v4 or derived key: groupId + metric + periodKey).
  final String id;

  /// The coaching group this ranking belongs to.
  final String groupId;

  final CoachingRankingMetric metric;
  final CoachingRankingPeriod period;

  /// Human-readable period key, e.g. "2026-W08" or "2026-02".
  final String periodKey;

  /// Start of the ranking window (ms since epoch, UTC).
  final int startsAtMs;

  /// End of the ranking window (ms since epoch, UTC).
  final int endsAtMs;

  /// Ordered entries (rank 1 first).
  final List<CoachingRankingEntryEntity> entries;

  /// When this snapshot was computed (ms since epoch, UTC).
  final int computedAtMs;

  const CoachingGroupRankingEntity({
    required this.id,
    required this.groupId,
    required this.metric,
    required this.period,
    required this.periodKey,
    required this.startsAtMs,
    required this.endsAtMs,
    this.entries = const [],
    required this.computedAtMs,
  });

  /// Whether [metric] ranks by lowest value (pace: lower = faster).
  bool get isLowerBetter => metric == CoachingRankingMetric.bestPace;

  /// Number of athletes in this ranking snapshot.
  int get athleteCount => entries.length;

  @override
  List<Object?> get props => [
        id,
        groupId,
        metric,
        period,
        periodKey,
        startsAtMs,
        endsAtMs,
        entries,
        computedAtMs,
      ];
}
