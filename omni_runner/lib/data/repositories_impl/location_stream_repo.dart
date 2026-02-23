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
  geo.LocationAccuracy _mapAccuracy(LocationAccuracy accuracy) {
    return switch (accuracy) {
      LocationAccuracy.low => geo.LocationAccuracy.low,
      LocationAccuracy.medium => geo.LocationAccuracy.medium,
      LocationAccuracy.high => geo.LocationAccuracy.best,
    };
  }
}
