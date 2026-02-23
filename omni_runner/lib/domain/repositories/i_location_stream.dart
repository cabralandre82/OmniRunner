import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/location_settings_entity.dart';

/// Contract for streaming GPS location updates.
///
/// Domain interface. Implementation lives in infrastructure.
/// Provides a reactive stream of [LocationPointEntity] during workouts.
///
/// Dependency direction: infrastructure -> domain (implements this).
abstract interface class ILocationStream {
  /// Start streaming location updates.
  ///
  /// Returns a broadcast stream of [LocationPointEntity].
  /// Stream emits a new point each time the device moves
  /// beyond [settings.distanceFilterMeters].
  ///
  /// If [settings] is not provided, implementations should use
  /// `const LocationSettingsEntity()` as default.
  ///
  /// Caller is responsible for:
  /// - Ensuring permission is granted before calling
  /// - Cancelling the subscription when done
  ///
  /// Stream errors are emitted as [LocationFailure] types.
  Stream<LocationPointEntity> watch([
    LocationSettingsEntity settings = const LocationSettingsEntity(),
  ]);
}
