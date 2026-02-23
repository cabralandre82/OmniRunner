import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Calculates smoothed pace using Exponential Moving Average (EMA).
///
/// Pace is expressed as **seconds per kilometer** internally.
/// UI layer converts to min:sec/km for display.
///
/// EMA formula: smoothed = alpha * current + (1 - alpha) * previous
///
/// Protections:
/// - Division by zero: returns null if deltaTime == 0 or deltaDist < minSegmentMeters
/// - Outlier rejection: ignores segments with pace outside plausible range
///
/// Conforms to [O4]: single `call()` method.
final class CalculatePace {
  /// EMA smoothing factor (0.0–1.0).
  /// Higher = more reactive to current segment.
  /// Lower = smoother, more stable.
  final double alpha;

  /// Minimum segment distance in meters to consider valid.
  /// Segments shorter than this produce unreliable pace.
  final double minSegmentMeters;

  /// Minimum plausible pace in sec/km (~1:40/km = 100 sec/km).
  /// Anything faster is likely GPS error.
  final double minPaceSecPerKm;

  /// Maximum plausible pace in sec/km (~30:00/km = 1800 sec/km).
  /// Anything slower is likely stationary or GPS drift.
  final double maxPaceSecPerKm;

  const CalculatePace({
    this.alpha = 0.3,
    this.minSegmentMeters = 3.0,
    this.minPaceSecPerKm = 100.0,
    this.maxPaceSecPerKm = 1800.0,
  });

  /// Calculate smoothed pace from a list of GPS points.
  ///
  /// Returns pace in **seconds per kilometer**, or `null` if
  /// insufficient valid segments exist.
  ///
  /// Points are processed in order. Each consecutive pair forms
  /// a segment. Invalid segments (too short, zero time, implausible
  /// pace) are skipped.
  double? call(List<LocationPointEntity> points) {
    if (points.length < 2) return null;

    double? smoothedPace;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      final deltaMs = curr.timestampMs - prev.timestampMs;
      if (deltaMs <= 0) continue;

      final distMeters = haversineMeters(
        lat1: prev.lat,
        lng1: prev.lng,
        lat2: curr.lat,
        lng2: curr.lng,
      );

      if (distMeters < minSegmentMeters) continue;

      // pace = (deltaTime in seconds) / (distance in km)
      final deltaSeconds = deltaMs / 1000.0;
      final distKm = distMeters / 1000.0;
      final segmentPace = deltaSeconds / distKm;

      // Reject implausible pace values.
      if (segmentPace < minPaceSecPerKm || segmentPace > maxPaceSecPerKm) {
        continue;
      }

      // Apply EMA.
      if (smoothedPace == null) {
        smoothedPace = segmentPace;
      } else {
        smoothedPace = alpha * segmentPace + (1 - alpha) * smoothedPace;
      }
    }

    return smoothedPace;
  }
}
