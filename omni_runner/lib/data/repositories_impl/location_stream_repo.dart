import 'package:geolocator/geolocator.dart' as geo;

import 'package:omni_runner/data/datasources/geolocator_location_stream.dart';
import 'package:omni_runner/data/mappers/position_mapper.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/location_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_location_stream.dart';

/// Concrete implementation of [ILocationStream].
///
/// Delegates to [GeolocatorLocationStream] and uses [PositionMapper]
/// to translate [geo.Position] (plugin) → [LocationPointEntity] (domain).
///
/// Dependency direction: data → domain (implements interface).
class LocationStreamRepo implements ILocationStream {
  final GeolocatorLocationStream _datasource;

  const LocationStreamRepo({
    required GeolocatorLocationStream datasource,
  }) : _datasource = datasource;

  @override
  Stream<LocationPointEntity> watch([
    LocationSettingsEntity settings = const LocationSettingsEntity(),
  ]) {
    return _datasource
        .positionStream(
          distanceFilter: settings.distanceFilterMeters,
          accuracy: _mapAccuracy(settings.accuracy),
        )
        .map(PositionMapper.fromPosition);
  }

  /// Maps domain [LocationAccuracy] to geolocator [geo.LocationAccuracy].
  ///
  /// L21-06: [LocationAccuracy.bestForNavigation] maps to the platform
  /// "finest available" — on iOS this enables multi-constellation GNSS
  /// + CoreLocation `kCLLocationAccuracyBestForNavigation` (used when
  /// the user is in `RecordingMode.performance`). On Android the
  /// geolocator plugin uses the same enum; it resolves to the
  /// high-accuracy fused provider.
  geo.LocationAccuracy _mapAccuracy(LocationAccuracy accuracy) {
    return switch (accuracy) {
      LocationAccuracy.low => geo.LocationAccuracy.low,
      LocationAccuracy.medium => geo.LocationAccuracy.medium,
      LocationAccuracy.high => geo.LocationAccuracy.best,
      LocationAccuracy.bestForNavigation => geo.LocationAccuracy.bestForNavigation,
    };
  }
}
