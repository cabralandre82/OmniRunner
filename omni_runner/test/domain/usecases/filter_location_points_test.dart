import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';

LocationPointEntity _pt(double lat, double lng, int ms, [double? acc]) {
  return LocationPointEntity(
    lat: lat, lng: lng, accuracy: acc, timestampMs: ms,
  );
}

void main() {
  late FilterLocationPoints filter;

  setUp(() {
    filter = const FilterLocationPoints();
  });

  group('FilterLocationPoints', () {
    // ── Edge cases ──

    test('empty list returns empty list', () {
      expect(filter([]), isEmpty);
    });

    test('single good point is accepted', () {
      final pts = [_pt(0.0, 0.0, 0, 5.0)];
      final result = filter(pts);
      expect(result, hasLength(1));
      expect(result.first, equals(pts.first));
    });

    // ── Filter 1: Accuracy ──

    test('point with accuracy > 15m is rejected', () {
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.001, 0.0, 5000, 20.0)];
      expect(filter(pts), hasLength(1));
    });

    test('point with accuracy exactly 15m is accepted', () {
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.001, 0.0, 30000, 15.0)];
      expect(filter(pts), hasLength(2));
    });

    test('point with null accuracy is accepted', () {
      final pts = [_pt(0.0, 0.0, 0), _pt(0.001, 0.0, 30000)];
      expect(filter(pts), hasLength(2));
    });

    test('all points with bad accuracy returns empty', () {
      final pts = [_pt(0.0, 0.0, 0, 50.0), _pt(0.001, 0.0, 5000, 50.0)];
      expect(filter(pts), isEmpty);
    });

    // ── Filter 2: Speed sanity ──

    test('teleportation is rejected (speed > 11.5 m/s)', () {
      // 111.19m in 1s = 111.19 m/s
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.001, 0.0, 1000, 5.0)];
      expect(filter(pts), hasLength(1));
    });

    test('fast but plausible speed is accepted', () {
      // 111.19m in 11.2s = 9.93 m/s (< 11.5)
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.001, 0.0, 11200, 5.0)];
      expect(filter(pts), hasLength(2));
    });

    test('speed just under limit is accepted', () {
      // 111.19m in 9.7s = 11.46 m/s (< 11.5)
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.001, 0.0, 9700, 5.0)];
      expect(filter(pts), hasLength(2));
    });

    test('zero deltaTime skips speed check, applies drift', () {
      // deltaMs == 0 → speed check skipped; 111m > 3m → accepted
      final pts = [_pt(0.0, 0.0, 1000, 5.0), _pt(0.001, 0.0, 1000, 5.0)];
      expect(filter(pts), hasLength(2));
    });

    // ── Filter 3: Drift ──

    test('drift below 3m is rejected', () {
      // ~1m movement
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.000009, 0.0, 5000, 5.0)];
      expect(filter(pts), hasLength(1));
    });

    test('movement above 3m is accepted', () {
      // ~5m movement
      final pts = [_pt(0.0, 0.0, 0, 5.0), _pt(0.000045, 0.0, 5000, 5.0)];
      expect(filter(pts), hasLength(2));
    });

    test('stationary with GPS jitter is fully filtered', () {
      // All movements < 3m from anchor
      final pts = [
        _pt(0.0, 0.0, 0, 5.0),
        _pt(0.000010, 0.0, 1000, 5.0),       // ~1.1m
        _pt(-0.000005, 0.000010, 2000, 5.0),  // ~2.0m from anchor
        _pt(0.000008, -0.000005, 3000, 5.0),  // ~2.2m from anchor
      ];
      expect(filter(pts), hasLength(1));
    });

    // ── Pipeline integration ──

    test('filters are applied in order: accuracy first', () {
      // Point 2: bad accuracy AND would be speed outlier → caught by accuracy
      final pts = [
        _pt(0.0, 0.0, 0, 5.0),
        _pt(0.1, 0.0, 1000, 50.0),   // bad accuracy → skip
        _pt(0.001, 0.0, 30000, 5.0),  // measured from point 0
      ];
      final result = filter(pts);
      expect(result, hasLength(2));
      expect(result[0].lat, 0.0);
      expect(result[1].lat, 0.001);
    });

    test('speed check uses last accepted, not previous raw', () {
      final pts = [
        _pt(0.0, 0.0, 0, 5.0),
        _pt(0.005, 0.0, 10000, 50.0),  // rejected (accuracy)
        _pt(0.001, 0.0, 30000, 5.0),   // 111m from pt0 in 30s = 3.7 m/s
      ];
      final result = filter(pts);
      expect(result, hasLength(2));
    });

    test('realistic run: good points pass through', () {
      // 10 points, ~100m apart, 30s intervals = ~3.34 m/s
      final pts = List.generate(
        10,
        (i) => _pt(i * 0.0009, 0.0, i * 30000, 5.0),
      );
      expect(filter(pts), hasLength(10));
    });

    test('realistic run with noise: outliers removed', () {
      final pts = [
        _pt(0.0, 0.0, 0, 5.0),           // 0: anchor
        _pt(0.0009, 0.0, 30000, 5.0),     // 1: ok (100m/30s=3.3m/s)
        _pt(0.0018, 0.0, 60000, 30.0),    // 2: bad accuracy
        _pt(0.010, 0.0, 61000, 5.0),      // 3: teleport (1012m/31s=32.6m/s)
        _pt(0.0027, 0.0, 90000, 5.0),     // 4: ok (200m/60s=3.3m/s from pt1)
        _pt(0.00270001, 0.0, 91000, 5.0), // 5: drift (0.001m)
        _pt(0.0036, 0.0, 120000, 5.0),    // 6: ok (100m/30s=3.3m/s from pt4)
      ];
      final result = filter(pts);
      // Accepted: 0, 1, 4, 6
      expect(result, hasLength(4));
      expect(result[0].lat, 0.0);
      expect(result[1].lat, closeTo(0.0009, 1e-6));
      expect(result[2].lat, closeTo(0.0027, 1e-6));
      expect(result[3].lat, closeTo(0.0036, 1e-6));
    });

    // ── Custom configuration ──

    test('custom thresholds are respected', () {
      const strict = FilterLocationPoints(
        maxAccuracyMeters: 5.0,
        maxSpeedMps: 5.0,
        minMovementMeters: 10.0,
      );
      // ~5m movement < 10m minMovement → rejected
      final pts = [
        _pt(0.0, 0.0, 0, 3.0),
        _pt(0.000045, 0.0, 5000, 3.0),
      ];
      expect(strict(pts), hasLength(1));
    });

    test('original list is not modified', () {
      final pts = [
        _pt(0.0, 0.0, 0, 5.0),
        _pt(0.001, 0.0, 5000, 50.0), // bad accuracy
      ];
      final original = List<LocationPointEntity>.from(pts);
      filter(pts);
      expect(pts, equals(original));
    });
  });
}
