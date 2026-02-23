import 'package:geolocator/geolocator.dart' as geo;

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Maps geolocator [geo.Position] to domain [LocationPointEntity].
///
/// Data layer only. Isolates platform-specific models from the domain
/// layer, maintaining Clean Architecture boundary.
///
/// No state. No side effects. Pure mapping function.
abstract final class PositionMapper {
  /// Convert [geo.Position] to [LocationPointEntity].
  ///
  /// Field mapping:
  /// - `latitude`  → `lat`
  /// - `longitude` → `lng`
  /// - `altitude`  → `alt` (always provided by geolocator, 0.0 = sea level)
  /// - `accuracy`  → `accuracy` (horizontal accuracy in meters)
  /// - `speed`     → `speed` (m/s, 0.0 = stationary)
  /// - `heading`   → `bearing` (degrees 0-360, 0.0 = north/unknown)
  /// - `timestamp` → `timestampMs` (DateTime → milliseconds since epoch)
  ///
  /// Not mapped (domain doesn't need them):
  /// - `altitudeAccuracy`, `headingAccuracy`, `speedAccuracy`
  /// - `floor`, `isMocked`
  ///
  /// Note: geolocator provides all fields as non-nullable doubles.
  /// Domain entity accepts nullable fields for other data sources.
  /// This mapper always provides all values.
  static LocationPointEntity fromPosition(geo.Position position) {
    return LocationPointEntity(
      lat: position.latitude,
      lng: position.longitude,
      alt: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      bearing: position.heading,
      timestampMs: position.timestamp.millisecondsSinceEpoch,
    );
  }
}
