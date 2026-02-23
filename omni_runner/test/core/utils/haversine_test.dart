import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/core/utils/haversine.dart';

void main() {
  group('haversineMeters', () {
    test('same point returns 0 meters', () {
      final result = haversineMeters(
        lat1: -23.550520,
        lng1: -46.633308,
        lat2: -23.550520,
        lng2: -46.633308,
      );

      expect(result, 0.0);
    });

    test('1 degree latitude at equator ≈ 111,195 meters', () {
      final result = haversineMeters(
        lat1: 0.0,
        lng1: 0.0,
        lat2: 1.0,
        lng2: 0.0,
      );

      // Computed: 111,194.92664455874
      expect(result, closeTo(111194.93, 0.01));
    });

    test('1 degree longitude at equator ≈ 111,195 meters', () {
      final result = haversineMeters(
        lat1: 0.0,
        lng1: 0.0,
        lat2: 0.0,
        lng2: 1.0,
      );

      // Identical to latitude at equator.
      expect(result, closeTo(111194.93, 0.01));
    });

    test('known distance: Sao Paulo to Rio de Janeiro', () {
      final result = haversineMeters(
        lat1: -23.5505,
        lng1: -46.6333,
        lat2: -22.9068,
        lng2: -43.1729,
      );

      // Computed: 360,748.82
      expect(result, closeTo(360749, 1));
    });

    test('known distance: London to Paris', () {
      final result = haversineMeters(
        lat1: 51.5074,
        lng1: -0.1278,
        lat2: 48.8566,
        lng2: 2.3522,
      );

      // Computed: 343,556.06
      expect(result, closeTo(343556, 1));
    });

    test('short running distance: ~100 meters', () {
      final result = haversineMeters(
        lat1: -23.5505,
        lng1: -46.6333,
        lat2: -23.5505,
        lng2: -46.6323,
      );

      // Computed: 101.93
      expect(result, closeTo(101.93, 0.01));
    });

    test('order does not matter (symmetric)', () {
      final ab = haversineMeters(
        lat1: -23.5505,
        lng1: -46.6333,
        lat2: -22.9068,
        lng2: -43.1729,
      );

      final ba = haversineMeters(
        lat1: -22.9068,
        lng1: -43.1729,
        lat2: -23.5505,
        lng2: -46.6333,
      );

      expect(ab, equals(ba));
    });

    test('antipodal points: half circumference', () {
      final result = haversineMeters(
        lat1: 90.0,
        lng1: 0.0,
        lat2: -90.0,
        lng2: 0.0,
      );

      // Computed: 20,015,086.796 (pi * R)
      expect(result, closeTo(20015086.80, 0.01));
    });

    test('very small distance: ~5 meters (GPS precision scale)', () {
      final result = haversineMeters(
        lat1: 0.0,
        lng1: 0.0,
        lat2: 0.000045,
        lng2: 0.0,
      );

      // Computed: 5.0038
      expect(result, closeTo(5.004, 0.001));
    });

    test('crossing the prime meridian', () {
      final result = haversineMeters(
        lat1: 51.5074,
        lng1: -0.5,
        lat2: 51.5074,
        lng2: 0.5,
      );

      // Computed: 69,208.69
      expect(result, closeTo(69208.69, 0.01));
    });

    test('crossing the international date line', () {
      final result = haversineMeters(
        lat1: 0.0,
        lng1: 179.5,
        lat2: 0.0,
        lng2: -179.5,
      );

      // 1 degree at equator. Computed: 111,194.9266
      expect(result, closeTo(111194.93, 0.01));
    });
  });
}
