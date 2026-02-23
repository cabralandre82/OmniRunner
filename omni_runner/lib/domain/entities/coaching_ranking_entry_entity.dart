import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';

/// A single athlete's row inside a coaching group ranking.
///
/// Immutable value object. Ties share the same [rank]; the next rank skips
/// (dense ranking: 1, 1, 3 — not 1, 1, 2).
///
/// For [CoachingRankingMetric.bestPace], lower [value] is better.
/// For all other metrics, higher [value] is better.
///
/// See Phase 16 — Assessoria Mode § Ranking Engine.
final class CoachingRankingEntryEntity extends Equatable {
  /// User ID of the ranked athlete.
  final String userId;

  /// Cached for offline display.
  final String displayName;

  /// Metric value:
  /// - [volumeDistance]: meters (double)
  /// - [totalTime]: milliseconds (double, from int)
  /// - [bestPace]: sec/km (double, lower = faster)
  /// - [consistencyDays]: day count (double, from int)
  final double value;

  /// 1-indexed rank within the group for this metric and period.
  final int rank;

  /// Number of verified sessions contributing to this metric value.
  final int sessionCount;

  const CoachingRankingEntryEntity({
    required this.userId,
    required this.displayName,
    required this.value,
    required this.rank,
    this.sessionCount = 0,
  });

  @override
  List<Object?> get props => [userId, displayName, value, rank, sessionCount];
}
