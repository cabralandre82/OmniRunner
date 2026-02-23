import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';

void main() {
  const filter = FilterLocationPoints();
  const accumulate = AccumulateDistance();
  const pace = CalculatePace();

  group('FilterLocationPoints — edge cases', () {
    test('empty list returns empty', () {
      expect(filter([]), isEmpty);
    });

    test('single point returns single point', () {
      final pts = [
        const LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
      ];
      expect(filter(pts).length, 1);
    });

    test('points with null accuracy pass through', () {
      final pts = [
        const LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
        const LocationPointEntity(lat: 0.0001, lng: 0.0, timestampMs: 5000),
      ];
      final result = filter(pts);
      expect(result.length, 2);
    });

    test('all points with bad accuracy are filtered out', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 100, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.001, lng: 0.0, accuracy: 100, timestampMs: 5000),
      ];
      expect(filter(pts), isEmpty);
    });

    test('identical timestamps: speed check skipped, drift check applies', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 1000),
        const LocationPointEntity(
            lat: 0.001, lng: 0.0, accuracy: 5, timestampMs: 1000),
      ];
      final result = filter(pts);
      expect(result.length, 2);
    });

    test('micro-movements below drift threshold are filtered', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.000001, lng: 0.0, accuracy: 5, timestampMs: 5000),
      ];
      final result = filter(pts);
      expect(result.length, 1);
    });

    test('teleportation (speed > 11.5 m/s) is filtered', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.01, lng: 0.0, accuracy: 5, timestampMs: 1000),
      ];
      final result = filter(pts);
      expect(result.length, 1);
    });
  });

  group('AccumulateDistance — edge cases', () {
    test('empty list returns 0.0', () {
      expect(accumulate([]), 0.0);
    });

    test('single point returns 0.0', () {
      final pts = [
        const LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
      ];
      expect(accumulate(pts), 0.0);
    });

    test('stationary points return 0.0', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 5000),
      ];
      expect(accumulate(pts), 0.0);
    });
  });

  group('CalculatePace — edge cases', () {
    test('empty list returns null', () {
      expect(pace([]), isNull);
    });

    test('single point returns null', () {
      final pts = [
        const LocationPointEntity(lat: 0.0, lng: 0.0, timestampMs: 0),
      ];
      expect(pace(pts), isNull);
    });

    test('stationary points return null', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 5000),
      ];
      expect(pace(pts), isNull);
    });

    test('implausibly fast pace is rejected', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.01, lng: 0.0, accuracy: 5, timestampMs: 100),
      ];
      expect(pace(pts), isNull);
    });
  });

  group('GPS signal loss simulation', () {
    test('large gap between points: moving time excludes gap', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.0001, lng: 0.0, accuracy: 5, timestampMs: 5000),
        // 5-minute gap (tunnel)
        const LocationPointEntity(
            lat: 0.0002, lng: 0.0, accuracy: 5, timestampMs: 305000),
        const LocationPointEntity(
            lat: 0.0003, lng: 0.0, accuracy: 5, timestampMs: 310000),
      ];
      final filtered = filter(pts);
      expect(filtered.length, greaterThanOrEqualTo(2));
      final dist = accumulate(filtered);
      expect(dist, greaterThan(0));
    });

    test('all poor accuracy after gap: distance not inflated', () {
      final pts = [
        const LocationPointEntity(
            lat: 0.0, lng: 0.0, accuracy: 5, timestampMs: 0),
        const LocationPointEntity(
            lat: 0.0001, lng: 0.0, accuracy: 5, timestampMs: 5000),
        // After tunnel: poor accuracy
        const LocationPointEntity(
            lat: 0.01, lng: 0.0, accuracy: 50, timestampMs: 305000),
        const LocationPointEntity(
            lat: 0.011, lng: 0.0, accuracy: 50, timestampMs: 310000),
        // Good accuracy returns
        const LocationPointEntity(
            lat: 0.0002, lng: 0.0, accuracy: 5, timestampMs: 315000),
      ];
      final filtered = filter(pts);
      final dist = accumulate(filtered);
      // Distance should not include the 50m-accuracy jump
      expect(dist, lessThan(500));
    });
  });
}
