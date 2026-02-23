import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Accumulates total distance from GPS points, filtering out noise.
///
/// Rules:
/// 1. Points with accuracy > [maxAccuracyMeters] are ignored.
/// 2. Movements < [minMovementMeters] are ignored (GPS drift).
/// 3. Distance is summed via Haversine between consecutive accepted points.
///
/// Conforms to [O4]: single `call()` method.
final class AccumulateDistance {
  /// Maximum acceptable horizontal accuracy in meters.
  /// Points with accuracy worse than this are discarded.
  final double maxAccuracyMeters;

  /// Minimum movement in meters to count as real movement.
  /// Prevents GPS drift from inflating distance.
  final double minMovementMeters;

  const AccumulateDistance({
    this.maxAccuracyMeters = 25.0,
    this.minMovementMeters = 3.0,
  });

  /// Calculate total distance in meters from a list of GPS points.
  ///
  /// Returns total distance in **meters** (double).
  /// Returns 0.0 if fewer than 2 acceptable points.
  ///
  /// Points are processed in order. Each point is either accepted
  /// or rejected based on accuracy and minimum movement thresholds.
  double call(List<LocationPointEntity> points) {
    var totalMeters = 0.0;
    LocationPointEntity? lastAccepted;

    for (final point in points) {
      // Rule 1: Skip points with poor accuracy.
      if (point.accuracy != null && point.accuracy! > maxAccuracyMeters) {
        continue;
      }

      // First acceptable point becomes the anchor.
      if (lastAccepted == null) {
        lastAccepted = point;
        continue;
      }

      // Calculate distance from last accepted point.
      final segment = haversineMeters(
        lat1: lastAccepted.lat,
        lng1: lastAccepted.lng,
        lat2: point.lat,
        lng2: point.lng,
      );

      // Rule 2: Skip if movement is below drift threshold.
      if (segment < minMovementMeters) {
        continue;
      }

      totalMeters += segment;
      lastAccepted = point;
    }

    return totalMeters;
  }
}
