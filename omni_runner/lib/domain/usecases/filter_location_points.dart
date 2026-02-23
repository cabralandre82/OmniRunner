import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Filters a list of GPS points, removing noise and outliers.
///
/// Pipeline (applied in order):
/// 1. **Accuracy filter:** reject points with horizontal accuracy > [maxAccuracyMeters]
/// 2. **Speed sanity:** reject points implying speed > [maxSpeedMps] from last accepted
/// 3. **Drift filter:** reject points < [minMovementMeters] from last accepted
///
/// Returns a new list containing only accepted points.
/// Original list is not modified.
///
/// Conforms to [O4]: single `call()` method.
final class FilterLocationPoints {
  /// Maximum acceptable horizontal accuracy in meters.
  final double maxAccuracyMeters;

  /// Maximum plausible speed in meters per second.
  /// Default 11.5 m/s ≈ 41.4 km/h (sprint world record pace).
  final double maxSpeedMps;

  /// Minimum movement in meters to count as real movement.
  final double minMovementMeters;

  const FilterLocationPoints({
    this.maxAccuracyMeters = 25.0,
    this.maxSpeedMps = 11.5,
    this.minMovementMeters = 3.0,
  });

  /// Filter a list of GPS points, returning only accepted points.
  ///
  /// Points are processed in order. Each point is evaluated against
  /// the last accepted point for speed and drift checks.
  ///
  /// Returns an empty list if no points pass all filters.
  List<LocationPointEntity> call(List<LocationPointEntity> points) {
    if (points.isEmpty) return const [];

    final accepted = <LocationPointEntity>[];
    LocationPointEntity? lastAccepted;

    for (final point in points) {
      // Filter 1: Accuracy — reject inaccurate readings.
      if (point.accuracy != null && point.accuracy! > maxAccuracyMeters) {
        continue;
      }

      // First acceptable point becomes the anchor.
      if (lastAccepted == null) {
        lastAccepted = point;
        accepted.add(point);
        continue;
      }

      final distance = haversineMeters(
        lat1: lastAccepted.lat,
        lng1: lastAccepted.lng,
        lat2: point.lat,
        lng2: point.lng,
      );

      final deltaMs = point.timestampMs - lastAccepted.timestampMs;

      // Filter 2: Speed sanity — reject teleportation / GPS jumps.
      if (deltaMs > 0) {
        final speedMps = distance / (deltaMs / 1000.0);
        if (speedMps > maxSpeedMps) {
          continue;
        }
      }

      // Filter 3: Drift — reject micro-movements (GPS jitter).
      if (distance < minMovementMeters) {
        continue;
      }

      lastAccepted = point;
      accepted.add(point);
    }

    return accepted;
  }
}
