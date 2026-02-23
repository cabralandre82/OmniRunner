import 'dart:math' as math;

/// Calculates the great-circle distance between two points on Earth
/// using the Haversine formula.
///
/// Returns distance in **meters**.
///
/// Uses Earth radius of 6,371,000 meters (mean radius).
///
/// Pure function. No state. No side effects.
/// Domain-safe: no external dependencies.
///
/// Reference: https://en.wikipedia.org/wiki/Haversine_formula
double haversineMeters({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const earthRadiusMeters = 6371000.0;

  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);

  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1Rad) *
          math.cos(lat2Rad) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadiusMeters * c;
}

double _toRadians(double degrees) => degrees * (math.pi / 180.0);
