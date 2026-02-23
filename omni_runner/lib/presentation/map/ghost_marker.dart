import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Manages a semi-transparent ghost runner marker on the map.
///
/// Uses a GeoJSON point source + circle layer. Call [init] once after the
/// map style is loaded, then [update] on each tracking tick.
class GhostMarker {
  static const _srcId = 'ghost-marker-src';
  static const _layerId = 'ghost-marker-layer';

  final MapLibreMapController _ctrl;
  bool _added = false;

  GhostMarker(this._ctrl);

  /// Adds the source and layer to the map. Safe to call once.
  Future<void> init() async {
    if (_added) return;
    await _ctrl.addGeoJsonSource(_srcId, _emptyPoint());
    await _ctrl.addCircleLayer(
      _srcId,
      _layerId,
      const CircleLayerProperties(
        circleRadius: 10,
        circleColor: '#9C27B0',
        circleOpacity: 0.55,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    _added = true;
  }

  /// Moves the ghost dot to [pos]. Pass `null` to hide.
  Future<void> update(LocationPointEntity? pos) async {
    if (!_added) return;
    await _ctrl.setGeoJsonSource(
      _srcId,
      pos != null ? _pointGeo(pos.lat, pos.lng) : _emptyPoint(),
    );
  }

  static Map<String, dynamic> _emptyPoint() => {
        'type': 'FeatureCollection',
        'features': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _pointGeo(double lat, double lng) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'Point',
              'coordinates': [lng, lat],
            },
          },
        ],
      };
}
