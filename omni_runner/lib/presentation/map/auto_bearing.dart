import 'dart:math' as math;

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Determines the map camera bearing based on runner movement.
///
/// Presentation layer utility. Reads domain entities, produces
/// bearing values for the map camera.
///
/// Rules:
/// - If speed > [defaultMinSpeedMps], use the GPS bearing for rotation.
/// - If speed <= threshold (stationary/slow), keep the previous bearing.
/// - Prevents erratic map spinning when standing still.
abstract final class AutoBearing {
  /// Minimum speed (m/s) to trust GPS bearing. Below this, jitter.
  static const defaultMinSpeedMps = 1.0;

  /// Camera bearing from a single location point's GPS bearing field.
  ///
  /// Returns [fallback] (typically current camera bearing) if:
  /// - Speed is null or <= [minSpeedMps]
  /// - Bearing data is null
  static double fromPoint(
    LocationPointEntity point, {
    required double fallback,
    double minSpeedMps = defaultMinSpeedMps,
  }) {
    final speed = point.speed;
    final bearing = point.bearing;

    if (speed == null) return fallback;
    if (speed <= minSpeedMps) return fallback;
    if (bearing == null) return fallback;

    return bearing;
  }

  /// Camera bearing calculated from two consecutive points.
  ///
  /// Fallback for when GPS bearing field is unavailable.
  /// Uses flat-earth atan2 approximation (accurate at running scale).
  ///
  /// Returns [fallback] if points are too close (< ~1 m),
  /// timestamps are invalid, or speed is below threshold.
  static double fromTwoPoints(
    LocationPointEntity prev,
    LocationPointEntity curr, {
    required double fallback,
    double minSpeedMps = defaultMinSpeedMps,
  }) {
    final deltaMs = curr.timestampMs - prev.timestampMs;
    if (deltaMs <= 0) return fallback;

    final dLat = curr.lat - prev.lat;
    final dLng = curr.lng - prev.lng;

    // 0.000009° ≈ 1 m — below this is GPS noise.
    if (dLat.abs() < 0.000009 && dLng.abs() < 0.000009) return fallback;

    // If speed available and too slow, don't rotate.
    if (curr.speed != null && curr.speed! <= minSpeedMps) return fallback;

    // Flat-earth bearing via atan2.
    final bearingRad = math.atan2(dLng, dLat);
    var bearingDeg = bearingRad * (180.0 / math.pi);

    // Normalize to 0–360.
    if (bearingDeg < 0) bearingDeg += 360.0;

    return bearingDeg;
  }
}
