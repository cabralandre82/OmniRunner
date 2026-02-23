import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/map/polyline_builder.dart';

LocationPointEntity _pt(double lat, double lng, {int ts = 0}) {
  return LocationPointEntity(lat: lat, lng: lng, timestampMs: ts);
}

void main() {
  group('PolylineBuilder.fromPoints', () {
    test('empty list returns empty', () {
      expect(PolylineBuilder.fromPoints([]), isEmpty);
    });

    test('single point returns single LatLng', () {
      final result = PolylineBuilder.fromPoints([_pt(-23.55, -46.63)]);
      expect(result, hasLength(1));
      expect(result[0].latitude, closeTo(-23.55, 0.0001));
      expect(result[0].longitude, closeTo(-46.63, 0.0001));
    });

    test('maps all points without simplification', () {
      final points = [
        _pt(-23.550, -46.630),
        _pt(-23.551, -46.631),
        _pt(-23.552, -46.632),
      ];
      final result = PolylineBuilder.fromPoints(points);
      expect(result, hasLength(3));
      expect(result[0].latitude, closeTo(-23.550, 0.0001));
      expect(result[1].latitude, closeTo(-23.551, 0.0001));
      expect(result[2].latitude, closeTo(-23.552, 0.0001));
    });

    test('preserves lat/lng mapping order', () {
      final p = _pt(10.0, 20.0);
      final result = PolylineBuilder.fromPoints([p]);
      expect(result[0].latitude, closeTo(10.0, 0.0001));
      expect(result[0].longitude, closeTo(20.0, 0.0001));
    });

    test('simplification with threshold 0 returns all points', () {
      final points = List.generate(
        10,
        (i) => _pt(-23.55 + i * 0.00001, -46.63),
      );
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 0,
      );
      expect(result, hasLength(10));
    });

    test('simplification skips close points', () {
      // Points ~1m apart, threshold 5m → most skipped
      final points = List.generate(
        20,
        (i) => _pt(-23.55 + i * 0.00001, -46.63), // ~1.1m apart
      );
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 5.0,
      );
      // Should keep first, last, and some intermediate
      expect(result.length, lessThan(points.length));
      expect(result.first.latitude, closeTo(-23.55, 0.0001));
      expect(
        result.last.latitude,
        closeTo(points.last.lat, 0.0001),
      );
    });

    test('simplification always keeps first and last', () {
      final points = [
        _pt(0.0, 0.0),
        _pt(0.000001, 0.000001), // ~0.15m from first
        _pt(0.000002, 0.000002), // ~0.15m from prev
        _pt(1.0, 1.0),           // far away
      ];
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 100.0,
      );
      expect(result.first.latitude, closeTo(0.0, 0.0001));
      expect(result.last.latitude, closeTo(1.0, 0.0001));
    });

    test('two points with simplification returns both', () {
      final points = [_pt(0.0, 0.0), _pt(1.0, 1.0)];
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 50.0,
      );
      expect(result, hasLength(2));
    });

    test('negative threshold treated as no simplification', () {
      final points = List.generate(
        5,
        (i) => _pt(i * 0.001, 0.0),
      );
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: -10.0,
      );
      expect(result, hasLength(5));
    });

    test('large threshold keeps only first and last (plus intermediate far)', () {
      // All intermediate points < 10m apart, threshold 1000m
      final points = List.generate(
        50,
        (i) => _pt(-23.55 + i * 0.00001, -46.63),
      );
      final result = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 1000.0,
      );
      // First + last always kept, intermediates all too close
      expect(result, hasLength(2));
    });

    test('realistic run with simplification reduces count', () {
      // Simulate 30-min run: ~1800 points, ~5m spacing
      final points = List.generate(
        1800,
        (i) => _pt(
          -23.55 + i * 0.000045, // ~5m per step
          -46.63 + i * 0.000045,
        ),
      );
      final full = PolylineBuilder.fromPoints(points);
      final simplified = PolylineBuilder.fromPoints(
        points,
        simplifyThresholdMeters: 20.0,
      );
      expect(full, hasLength(1800));
      expect(simplified.length, lessThan(700));
      expect(simplified.length, greaterThan(10));
    });
  });
}
