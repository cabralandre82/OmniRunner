import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Result of auto-pause detection for a single evaluation.
///
/// Immutable. Suggests whether the runner appears to be stopped.
/// Does NOT change workout state — only suggests.
final class AutoPauseResult {
  /// Whether the detector suggests the runner is paused.
  final bool pauseSuggested;

  /// Duration in milliseconds the runner has been below speed threshold.
  /// Zero if not paused.
  final int stationaryDurationMs;

  const AutoPauseResult({
    required this.pauseSuggested,
    required this.stationaryDurationMs,
  });
}

/// Detects when a runner has stopped moving and suggests auto-pause.
///
/// Rules:
/// 1. Speed below [minSpeedMps] for at least [stationaryThresholdMs].
/// 2. Drift below [maxDriftMeters] confirms stationary (not just slow GPS).
///
/// This use case does NOT modify workout state.
/// It only returns a suggestion. The BLoC decides whether to act.
///
/// Conforms to [O4]: single `call()` method.
final class AutoPauseDetector {
  /// Minimum speed in m/s to be considered "moving".
  final double minSpeedMps;

  /// Time in ms below minSpeed before suggesting pause.
  final int stationaryThresholdMs;

  /// Maximum drift in meters to confirm truly stationary.
  final double maxDriftMeters;

  const AutoPauseDetector({
    this.minSpeedMps = 0.5,
    this.stationaryThresholdMs = 5000,
    this.maxDriftMeters = 5.0,
  });

  /// Evaluate the most recent GPS points to detect a pause.
  ///
  /// Requires at least 2 points. Walks backwards from the latest
  /// point to find when the runner last appeared to be moving.
  ///
  /// Returns [AutoPauseResult] with suggestion and duration.
  AutoPauseResult call(List<LocationPointEntity> points) {
    if (points.length < 2) {
      return const AutoPauseResult(
        pauseSuggested: false,
        stationaryDurationMs: 0,
      );
    }

    final latest = points.last;

    // Default: assume entire history is stationary.
    // Overwritten if a moving segment is found.
    var stationaryStartMs = points.first.timestampMs;

    for (var i = points.length - 2; i >= 0; i--) {
      final point = points[i];
      final next = points[i + 1];

      final deltaMs = next.timestampMs - point.timestampMs;
      if (deltaMs <= 0) continue;

      // Use GPS-reported speed if available, else calculate.
      final double speedMps;
      if (next.speed != null && next.speed! >= 0) {
        speedMps = next.speed!;
      } else {
        final dist = haversineMeters(
          lat1: point.lat,
          lng1: point.lng,
          lat2: next.lat,
          lng2: next.lng,
        );
        speedMps = dist / (deltaMs / 1000.0);
      }

      // Check drift between this point and the latest point.
      final driftFromLatest = haversineMeters(
        lat1: point.lat,
        lng1: point.lng,
        lat2: latest.lat,
        lng2: latest.lng,
      );

      // If speed is above threshold OR significant drift → moving.
      if (speedMps >= minSpeedMps || driftFromLatest > maxDriftMeters) {
        stationaryStartMs = next.timestampMs;
        break;
      }
    }

    final stationaryDurationMs = latest.timestampMs - stationaryStartMs;

    return AutoPauseResult(
      pauseSuggested: stationaryDurationMs >= stationaryThresholdMs,
      stationaryDurationMs:
          stationaryDurationMs < 0 ? 0 : stationaryDurationMs,
    );
  }
}
