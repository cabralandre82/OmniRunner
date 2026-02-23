import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';

/// Helper to create a [LocationPointEntity] with minimal boilerplate.
LocationPointEntity _point({
  required double lat,
  required double lng,
  double? accuracy,
  int timestampMs = 0,
}) {
  return LocationPointEntity(
    lat: lat,
    lng: lng,
    accuracy: accuracy,
    timestampMs: timestampMs,
  );
}

void main() {
  late AccumulateDistance accumulate;

  setUp(() {
    accumulate = const AccumulateDistance();
  });

  group('AccumulateDistance', () {
    test('empty list returns 0', () {
      expect(accumulate([]), 0.0);
    });

    test('single point returns 0', () {
      final points = [_point(lat: -23.5505, lng: -46.6333, accuracy: 5.0)];

      expect(accumulate(points), 0.0);
    });

    test('two points with good accuracy sums distance', () {
      // 0.001 deg lng at SP latitude ≈ 101.93m
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 5.0),
      ];

      final result = accumulate(points);

      expect(result, closeTo(101.93, 0.01));
    });

    test('drift below 3m is NOT summed', () {
      // 0.000009 deg ≈ 1.0m (GPS drift)
      final points = [
        _point(lat: 0.0, lng: 0.0, accuracy: 5.0),
        _point(lat: 0.000009, lng: 0.0, accuracy: 5.0),
      ];

      expect(accumulate(points), 0.0);
    });

    test('drift just above threshold IS summed', () {
      // 0.000027 deg ≈ 3.002m (just above 3.0m threshold)
      final points = [
        _point(lat: 0.0, lng: 0.0, accuracy: 5.0),
        _point(lat: 0.000027, lng: 0.0, accuracy: 5.0),
      ];

      final result = accumulate(points);

      expect(result, closeTo(3.002, 0.001));
    });

    test('point with accuracy > 15m is skipped', () {
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 20.0), // bad accuracy
        _point(lat: -23.5505, lng: -46.6313, accuracy: 5.0),
      ];

      final result = accumulate(points);

      // Should skip middle point; distance = first to third ≈ 203.87m
      expect(result, closeTo(203.87, 0.01));
    });

    test('point with accuracy exactly 15m is accepted', () {
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 15.0),
      ];

      final result = accumulate(points);

      expect(result, closeTo(101.93, 0.01));
    });

    test('point with null accuracy is accepted', () {
      final points = [
        _point(lat: -23.5505, lng: -46.6333),
        _point(lat: -23.5505, lng: -46.6323),
      ];

      final result = accumulate(points);

      expect(result, closeTo(101.93, 0.01));
    });

    test('multiple valid segments sum correctly', () {
      // Three points, each ~102m apart
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6313, accuracy: 5.0),
      ];

      final result = accumulate(points);

      // ~101.93 + ~101.93 = ~203.87
      expect(result, closeTo(203.87, 0.1));
    });

    test('bad accuracy points in middle do not break chain', () {
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 5.0),
        _point(lat: -23.5505, lng: -46.6328, accuracy: 50.0), // skip
        _point(lat: -23.5505, lng: -46.6326, accuracy: 50.0), // skip
        _point(lat: -23.5505, lng: -46.6323, accuracy: 5.0),
      ];

      final result = accumulate(points);

      // Distance from first to last accepted ≈ 101.93m
      expect(result, closeTo(101.93, 0.01));
    });

    test('all points with bad accuracy returns 0', () {
      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 50.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 50.0),
        _point(lat: -23.5505, lng: -46.6313, accuracy: 50.0),
      ];

      expect(accumulate(points), 0.0);
    });

    test('stationary runner with drift does not accumulate', () {
      // Simulates standing still with GPS jitter (all < 3m)
      final points = [
        _point(lat: 0.0, lng: 0.0, accuracy: 5.0),
        _point(lat: 0.000010, lng: 0.0, accuracy: 5.0), // ~1.1m
        _point(lat: -0.000005, lng: 0.000010, accuracy: 5.0), // ~2.0m
        _point(lat: 0.000008, lng: -0.000005, accuracy: 5.0), // ~2.2m
        _point(lat: 0.000002, lng: 0.000003, accuracy: 5.0), // ~1.1m
      ];

      expect(accumulate(points), 0.0);
    });

    test('custom thresholds are respected', () {
      const strict = AccumulateDistance(
        maxAccuracyMeters: 5.0,
        minMovementMeters: 10.0,
      );

      final points = [
        _point(lat: 0.0, lng: 0.0, accuracy: 3.0),
        _point(lat: 0.000045, lng: 0.0, accuracy: 3.0), // ~5m, below 10m
      ];

      expect(strict(points), 0.0);
    });

    test('custom accuracy threshold rejects previously ok points', () {
      const strict = AccumulateDistance(maxAccuracyMeters: 5.0);

      final points = [
        _point(lat: -23.5505, lng: -46.6333, accuracy: 3.0),
        _point(lat: -23.5505, lng: -46.6323, accuracy: 8.0), // ok at 15, bad at 5
      ];

      expect(strict(points), 0.0);
    });

    test('long run accumulates correctly (~1km)', () {
      // 11 points, each ~102m apart along longitude
      final points = List.generate(
        11,
        (i) => _point(
          lat: -23.5505,
          lng: -46.6333 + (i * 0.001),
          accuracy: 5.0,
          timestampMs: i * 5000,
        ),
      );

      final result = accumulate(points);

      // 10 segments × ~101.93m ≈ 1019.3m
      expect(result, closeTo(1019.3, 1.0));
    });
  });
}
