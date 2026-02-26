import 'dart:math' as math;

import 'package:omni_runner/features/parks/domain/park_entity.dart';

/// Detects which park a run happened in based on GPS coordinates.
///
/// Uses ray-casting point-in-polygon algorithm on the park polygons.
/// Input: start coordinates (lat/lng) from Strava activity.
/// Output: the matching [ParkEntity], or null if not in any known park.
class ParkDetectionService {
  final List<ParkEntity> _parks;

  const ParkDetectionService(this._parks);

  /// Find the park containing the given point.
  /// Returns null if the point is not inside any known park.
  ParkEntity? detectPark(double lat, double lng) {
    for (final park in _parks) {
      if (_pointInPolygon(LatLng(lat, lng), park.polygon)) {
        return park;
      }
    }
    return null;
  }

  /// Find parks within [radiusM] meters of the given point.
  /// Useful for "nearby parks" when exact polygon match fails.
  List<ParkEntity> findNearby(double lat, double lng,
      {double radiusM = 500}) {
    return _parks.where((park) {
      final d = _haversineM(lat, lng, park.center.lat, park.center.lng);
      return d <= radiusM;
    }).toList()
      ..sort((a, b) {
        final da = _haversineM(lat, lng, a.center.lat, a.center.lng);
        final db = _haversineM(lat, lng, b.center.lat, b.center.lng);
        return da.compareTo(db);
      });
  }

  /// Ray-casting algorithm for point-in-polygon detection.
  static bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    var inside = false;
    final n = polygon.length;

    for (var i = 0, j = n - 1; i < n; j = i++) {
      final yi = polygon[i].lat;
      final xi = polygon[i].lng;
      final yj = polygon[j].lat;
      final xj = polygon[j].lng;

      if (((yi > point.lat) != (yj > point.lat)) &&
          (point.lng < (xj - xi) * (point.lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }

    return inside;
  }

  /// Haversine distance in meters between two points.
  static double _haversineM(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
