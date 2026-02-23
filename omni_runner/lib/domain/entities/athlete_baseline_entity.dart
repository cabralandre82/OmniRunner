import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

/// A reference snapshot of an athlete's metric value over a past window.
///
/// Used as the "starting point" for trend comparison. Recomputed
/// periodically (e.g. first N sessions, or rolling average of last 4 weeks).
///
/// One baseline per (userId, groupId, metric) — upserted when recalculated.
///
/// Immutable value object. See Phase 16 — Evolution Analytics Engine.
final class AthleteBaselineEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  final String userId;

  /// Coaching group context. Empty string if global (no group scope).
  final String groupId;

  final EvolutionMetric metric;

  /// Aggregated baseline value:
  /// - [avgPace]: sec/km
  /// - [avgDistance]: meters
  /// - [weeklyVolume]: meters/week
  /// - [weeklyFrequency]: sessions/week
  /// - [avgHeartRate]: BPM
  /// - [avgMovingTime]: milliseconds
  final double value;

  /// Number of sessions used to compute this baseline.
  final int sampleSize;

  /// Start of the window from which sessions were sampled (ms since epoch, UTC).
  final int windowStartMs;

  /// End of the window from which sessions were sampled (ms since epoch, UTC).
  final int windowEndMs;

  /// When this baseline was computed (ms since epoch, UTC).
  final int computedAtMs;

  const AthleteBaselineEntity({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.metric,
    required this.value,
    required this.sampleSize,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.computedAtMs,
  });

  /// Whether the baseline has enough data to be considered reliable.
  bool get isReliable => sampleSize >= 3;

  @override
  List<Object?> get props => [
        id,
        userId,
        groupId,
        metric,
        value,
        sampleSize,
        windowStartMs,
        windowEndMs,
        computedAtMs,
      ];
}
