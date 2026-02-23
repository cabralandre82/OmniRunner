import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_teleport.dart';

/// Helper: build a point at equator (1° lng ≈ 111 195 m).
LocationPointEntity _pt(
  double lng,
  int timestampMs, {
  double? accuracy = 5.0,
}) =>
    LocationPointEntity(
      lat: 0,
      lng: lng,
      timestampMs: timestampMs,
      accuracy: accuracy,
    );

/// Lng delta for a desired distance in meters (at equator).
double _lngDelta(double meters) => meters / 111195.0;

void main() {
  const detect = IntegrityDetectTeleport();

  group('IntegrityDetectTeleport', () {
    test('flag constant is TELEPORT', () {
      expect(IntegrityDetectTeleport.flag, 'TELEPORT');
    });

    test('empty list returns no violations', () {
      expect(detect(const []), isEmpty);
    });

    test('single point returns no violations', () {
      expect(detect([_pt(0, 0)]), isEmpty);
    });

    test('normal movement in 1s is clean', () {
      // 10 m in 1s = 10 m/s — well below 50 m/s threshold
      final pts = [_pt(0, 0), _pt(_lngDelta(10), 1000)];
      expect(detect(pts), isEmpty);
    });

    test('49m in 1s is clean (just below threshold)', () {
      final pts = [_pt(0, 0), _pt(_lngDelta(49), 1000)];
      expect(detect(pts), isEmpty);
    });

    test('exactly 50m in 1s is clean (threshold is strictly >)', () {
      // 50m / 1s = 50 m/s, threshold speed = 50/1 = 50 m/s, not >
      final pts = [_pt(0, 0), _pt(_lngDelta(50), 1000)];
      expect(detect(pts), isEmpty);
    });

    test('51m in 1s flags teleport', () {
      final pts = [_pt(0, 0), _pt(_lngDelta(51), 1000)];
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.fromMs, 0);
      expect(result.first.toMs, 1000);
      expect(result.first.distanceM, closeTo(51, 1));
      expect(result.first.impliedSpeedMps, closeTo(51, 1));
    });

    test('100m in 1s flags teleport', () {
      final pts = [_pt(0, 0), _pt(_lngDelta(100), 1000)];
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.impliedSpeedMps, closeTo(100, 1));
    });

    test('100m in 2s flags (normalised: 50 m/s threshold)', () {
      // 100m / 2s = 50 m/s. Threshold = 50/1 = 50 m/s. Not >. Clean.
      final pts = [_pt(0, 0), _pt(_lngDelta(100), 2000)];
      expect(detect(pts), isEmpty);
    });

    test('110m in 2s flags (55 m/s > threshold)', () {
      final pts = [_pt(0, 0), _pt(_lngDelta(110), 2000)];
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.impliedSpeedMps, closeTo(55, 1));
    });

    test('skip pair when prev has bad accuracy (>15m)', () {
      final pts = [
        _pt(0, 0, accuracy: 20),
        _pt(_lngDelta(100), 1000, accuracy: 5),
      ];
      expect(detect(pts), isEmpty);
    });

    test('skip pair when curr has bad accuracy (>15m)', () {
      final pts = [
        _pt(0, 0, accuracy: 5),
        _pt(_lngDelta(100), 1000, accuracy: 20),
      ];
      expect(detect(pts), isEmpty);
    });

    test('skip pair when prev has null accuracy', () {
      final pts = [
        _pt(0, 0, accuracy: null),
        _pt(_lngDelta(100), 1000, accuracy: 5),
      ];
      expect(detect(pts), isEmpty);
    });

    test('skip pair when curr has null accuracy', () {
      final pts = [
        _pt(0, 0, accuracy: 5),
        _pt(_lngDelta(100), 1000, accuracy: null),
      ];
      expect(detect(pts), isEmpty);
    });

    test('accuracy exactly 15m is accepted', () {
      final pts = [
        _pt(0, 0, accuracy: 15),
        _pt(_lngDelta(100), 1000, accuracy: 15),
      ];
      final result = detect(pts);
      expect(result, hasLength(1));
    });

    test('multiple teleports detected independently', () {
      final pts = [
        _pt(0, 0),
        _pt(_lngDelta(100), 1000), // teleport 1
        _pt(_lngDelta(110), 2000), // normal (10m)
        _pt(_lngDelta(250), 3000), // teleport 2
      ];
      final result = detect(pts);
      expect(result, hasLength(2));
      expect(result[0].fromMs, 0);
      expect(result[0].toMs, 1000);
      expect(result[1].fromMs, 2000);
      expect(result[1].toMs, 3000);
    });

    test('zero-delta timestamps are skipped gracefully', () {
      final pts = [
        _pt(0, 1000),
        _pt(_lngDelta(200), 1000), // same timestamp
      ];
      expect(detect(pts), isEmpty);
    });

    test('custom thresholds: maxJumpDistM', () {
      // 30m in 1s with threshold of 20m → teleport
      final pts = [_pt(0, 0), _pt(_lngDelta(30), 1000)];
      final result = detect(pts, maxJumpDistM: 20);
      expect(result, hasLength(1));
    });

    test('custom thresholds: maxAccuracyM', () {
      // Both accuracy=25, default maxAccuracy=15 → skipped
      // With maxAccuracy=30 → detected
      final pts = [
        _pt(0, 0, accuracy: 25),
        _pt(_lngDelta(100), 1000, accuracy: 25),
      ];
      expect(detect(pts), isEmpty);
      final result = detect(pts, maxAccuracyM: 30);
      expect(result, hasLength(1));
    });

    test('realistic run with normal GPS jitter is clean', () {
      // 3.7 m/s (4:30/km) with small jitter, 1s intervals
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 60; i++) {
        pts.add(_pt(_lngDelta(3.7 * i), i * 1000));
      }
      expect(detect(pts), isEmpty);
    });

    test('teleport sandwiched between good points is caught', () {
      final pts = [
        _pt(0, 0),
        _pt(_lngDelta(5), 1000),
        _pt(_lngDelta(200), 2000), // teleport from 5m to 200m
        _pt(_lngDelta(210), 3000),
      ];
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.fromMs, 1000);
      expect(result.first.toMs, 2000);
      expect(result.first.distanceM, closeTo(195, 2));
    });
  });
}
