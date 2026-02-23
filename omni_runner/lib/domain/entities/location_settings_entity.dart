import 'package:equatable/equatable.dart';

/// Configuration for GPS location tracking.
///
/// Immutable value object. No logic. No behavior.
/// Used as parameter for [ILocationStream.watch].
final class LocationSettingsEntity extends Equatable {
  /// Minimum distance in meters between location updates.
  final double distanceFilterMeters;

  /// Desired accuracy level for GPS readings.
  final LocationAccuracy accuracy;

  const LocationSettingsEntity({
    this.distanceFilterMeters = 5.0,
    this.accuracy = LocationAccuracy.high,
  });

  @override
  List<Object?> get props => [distanceFilterMeters, accuracy];
}

/// Desired accuracy level for GPS location readings.
///
/// Platform-agnostic. Maps to platform-specific values in infrastructure.
enum LocationAccuracy {
  /// Battery-optimized. ~100m accuracy. Not suitable for run tracking.
  low,

  /// Balanced. ~10-50m accuracy.
  medium,

  /// Best available. ~3-10m accuracy. Default for run tracking.
  high,
}
