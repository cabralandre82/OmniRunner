import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Converts domain GPS points to MapLibre [LatLng] polyline coordinates.
///
/// Presentation layer only. Bridges domain entities to map widget data.
/// Optionally applies distance-based simplification to reduce the number
/// of points rendered on the map for performance.
abstract final class PolylineBuilder {
  /// Convert [LocationPointEntity] list to MapLibre [LatLng] list.
  ///
  /// If [simplifyThresholdMeters] > 0, points closer than this distance
  /// to the previous accepted point are skipped.
  ///
  /// Recommended thresholds:
  /// - Live tracking: 5.0 m (matches GPS distanceFilter)
  /// - Post-run review: 2.0 m (higher detail)
  /// - Thumbnail/list: 20.0 m (minimal detail)
  static List<LatLng> fromPoints(
    List<LocationPointEntity> points, {
    double simplifyThresholdMeters = 0.0,
  }) {
    if (points.isEmpty) return const [];

    if (simplifyThresholdMeters <= 0) {
      return points
          .map((p) => LatLng(p.lat, p.lng))
          .toList(growable: false);
    }

    return _simplify(points, simplifyThresholdMeters);
  }

  /// Distance-based simplification.
  ///
  /// Keeps the first and last points always. Intermediate points are
  /// included only if >= [thresholdM] away from the last included point.
  /// Uses squared-degree approximation (no trig). At running scale
  /// (<50 km) the error is negligible.
  static List<LatLng> _simplify(
    List<LocationPointEntity> points,
    double thresholdM,
  ) {
    if (points.length <= 2) {
      return points
          .map((p) => LatLng(p.lat, p.lng))
          .toList(growable: false);
    }

    // 1 degree ≈ 111 195 m at equator. Squared to avoid sqrt.
    const mPerDeg = 111195.0;
    final threshDegSq = (thresholdM / mPerDeg) * (thresholdM / mPerDeg);

    final result = <LatLng>[LatLng(points.first.lat, points.first.lng)];
    var lastLat = points.first.lat;
    var lastLng = points.first.lng;

    for (var i = 1; i < points.length - 1; i++) {
      final dLat = points[i].lat - lastLat;
      final dLng = points[i].lng - lastLng;
      if (dLat * dLat + dLng * dLng >= threshDegSq) {
        result.add(LatLng(points[i].lat, points[i].lng));
        lastLat = points[i].lat;
        lastLng = points[i].lng;
      }
    }

    // Always include the last point.
    result.add(LatLng(points.last.lat, points.last.lng));
    return result;
  }
}
