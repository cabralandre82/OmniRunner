import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Result of comparing the runner's position against the ghost.
///
/// Immutable. Contains both spatial and temporal deltas.
final class GhostDelta {
  /// Distance delta in meters.
  /// Positive means the runner is **ahead** of the ghost.
  /// Negative means the runner is **behind** the ghost.
  final double deltaM;

  /// Time delta in milliseconds (optional).
  /// Positive means the runner is ahead by this many ms.
  /// Null when the ghost route is too short to estimate.
  final int? deltaTimeMs;

  const GhostDelta({required this.deltaM, this.deltaTimeMs});
}

/// Calculates the spatial delta between the runner and the ghost.
///
/// Uses [haversineMeters] for the distance. The sign convention is:
/// - Positive [deltaM] → runner is **ahead** of the ghost.
/// - Negative [deltaM] → runner is **behind** the ghost.
///
/// Returns `null` if the ghost position is not available.
///
/// Conforms to [O4]: single `call()` method.
final class CalculateGhostDelta {
  const CalculateGhostDelta();

  /// Compare [runnerPos] against [ghostPos].
  ///
  /// [runnerDistanceM] is the runner's accumulated distance so far.
  /// [ghostDistanceM] is the ghost's accumulated distance at its
  /// interpolated position. When both distances are available, the
  /// sign of [deltaM] is derived from the distance comparison
  /// (ahead = runner ran more). Otherwise falls back to raw
  /// haversine (unsigned).
  GhostDelta? call({
    required LocationPointEntity? runnerPos,
    required LocationPointEntity? ghostPos,
    double? runnerDistanceM,
    double? ghostDistanceM,
  }) {
    if (runnerPos == null || ghostPos == null) return null;

    final rawM = haversineMeters(
      lat1: runnerPos.lat,
      lng1: runnerPos.lng,
      lat2: ghostPos.lat,
      lng2: ghostPos.lng,
    );

    // When both accumulated distances are known, use them for sign.
    if (runnerDistanceM != null && ghostDistanceM != null) {
      final sign = runnerDistanceM >= ghostDistanceM ? 1.0 : -1.0;
      return GhostDelta(deltaM: sign * rawM);
    }

    // Fallback: unsigned distance (cannot determine ahead/behind).
    return GhostDelta(deltaM: rawM);
  }
}
