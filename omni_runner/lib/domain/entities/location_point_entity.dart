import 'package:equatable/equatable.dart';

/// A single GPS location point captured during a workout.
///
/// Immutable value object. No logic. No behavior.
/// Used as part of [WorkoutSessionEntity.route].
final class LocationPointEntity extends Equatable {
  /// Latitude in decimal degrees (-90 to 90).
  final double lat;

  /// Longitude in decimal degrees (-180 to 180).
  final double lng;

  /// Altitude in meters above sea level. Null if unavailable.
  final double? alt;

  /// Horizontal accuracy in meters. Null if unavailable.
  final double? accuracy;

  /// Speed in meters per second. Null if unavailable.
  final double? speed;

  /// Bearing in degrees (0-360). Null if unavailable.
  final double? bearing;

  /// Timestamp in milliseconds since Unix epoch (UTC).
  final int timestampMs;

  const LocationPointEntity({
    required this.lat,
    required this.lng,
    this.alt,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.timestampMs,
  });

  @override
  List<Object?> get props => [
        lat,
        lng,
        alt,
        accuracy,
        speed,
        bearing,
        timestampMs,
      ];
}
