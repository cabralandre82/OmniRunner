import 'package:geolocator/geolocator.dart' as geo;

/// Low-level datasource that wraps [geolocator] position stream.
///
/// Returns raw [geo.Position] from the plugin.
/// Translation to domain entities happens in the repository layer.
///
/// This class exists so the repository can be tested with a mock datasource.
class GeolocatorLocationStream {
  /// Start streaming position updates.
  ///
  /// [distanceFilter] — minimum displacement in meters between updates.
  /// [accuracy] — platform-specific accuracy constant from geolocator.
  ///
  /// Returns a stream of [geo.Position]. Caller must cancel subscription.
  Stream<geo.Position> positionStream({
    required double distanceFilter,
    required geo.LocationAccuracy accuracy,
  }) {
    final settings = geo.LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter.toInt(),
    );

    return geo.Geolocator.getPositionStream(
      locationSettings: settings,
    );
  }
}
