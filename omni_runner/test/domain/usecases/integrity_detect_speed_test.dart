import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_speed.dart';

/// Helper: build a point at equator where ~1 degree lng ≈ 111 195 m.
LocationPointEntity _pt(double lng, int timestampMs) =>
    LocationPointEntity(lat: 0, lng: lng, timestampMs: timestampMs);

/// Helper: lng delta for a desired distance in meters (at equator).
double _lngDelta(double meters) => meters / 111195.0;

void main() {
  const detect = IntegrityDetectSpeed();

  group('IntegrityDetectSpeed', () {
    test('flag constant is HIGH_SPEED', () {
      expect(IntegrityDetectSpeed.flag, 'HIGH_SPEED');
    });

    test('empty list returns no violations', () {
      expect(detect(const []), isEmpty);
    });

    test('single point returns no violations', () {
      expect(detect([_pt(0, 0)]), isEmpty);
    });

    test('two points below threshold returns no violations', () {
      // 10 m/s for 1 second — below 11.5
      final pts = [
        _pt(0, 0),
        _pt(_lngDelta(10), 1000),
      ];
      expect(detect(pts), isEmpty);
    });

    test('short burst above threshold (<10s) is tolerated', () {
      // 15 m/s for 5 seconds — above threshold but window too short
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 5; i++) {
        pts.add(_pt(_lngDelta(15.0 * i), i * 1000));
      }
      expect(detect(pts), isEmpty);
    });

    test('9.9s above threshold is still tolerated', () {
      // 12 m/s for 9.9 seconds — just below the 10s window
      final pts = <LocationPointEntity>[];
      const speedMps = 12.0;
      const dtMs = 990; // 10 segments of 990ms = 9.9s total
      for (var i = 0; i <= 10; i++) {
        pts.add(_pt(_lngDelta(speedMps * (dtMs / 1000.0) * i), i * dtMs));
      }
      expect(detect(pts), isEmpty);
    });

    test('exactly 10s above threshold triggers violation', () {
      // 12 m/s for 10 seconds — should flag
      final pts = <LocationPointEntity>[];
      const speedMps = 12.0;
      for (var i = 0; i <= 10; i++) {
        pts.add(_pt(_lngDelta(speedMps * i), i * 1000));
      }
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.startMs, 0);
      expect(result.first.endMs, 10000);
      expect(result.first.avgSpeedMps, closeTo(12.0, 0.5));
    });

    test('20s above threshold triggers exactly one violation', () {
      // 15 m/s for 20 seconds
      final pts = <LocationPointEntity>[];
      const speedMps = 15.0;
      for (var i = 0; i <= 20; i++) {
        pts.add(_pt(_lngDelta(speedMps * i), i * 1000));
      }
      final result = detect(pts);
      // First violation at 10s, then reset; second window 10-20s → second
      expect(result, hasLength(2));
      expect(result[0].endMs, 10000);
      expect(result[1].endMs, 20000);
    });

    test('high speed interrupted by slow segment resets window', () {
      // 12 m/s for 7s → 3 m/s for 1s → 12 m/s for 7s
      // Neither window reaches 10s
      final pts = <LocationPointEntity>[];
      const fast = 12.0;
      const slow = 3.0;
      var t = 0;
      var d = 0.0;
      // 7s fast
      for (var i = 0; i <= 7; i++) {
        pts.add(_pt(_lngDelta(d), t));
        if (i < 7) {
          d += fast;
          t += 1000;
        }
      }
      // 1s slow
      d += slow;
      t += 1000;
      pts.add(_pt(_lngDelta(d), t));
      // 7s fast
      for (var i = 0; i < 7; i++) {
        d += fast;
        t += 1000;
        pts.add(_pt(_lngDelta(d), t));
      }
      expect(detect(pts), isEmpty);
    });

    test('slow then fast 10s triggers violation only for fast part', () {
      // 5 m/s for 10s then 12 m/s for 12s, clean transition.
      // Slow loop: 10 pts at t=0..9s. Fast loop: 13 pts at t=10s..22s.
      // Transition pair (t=9s→10s) is 5 m/s (slow), so window starts
      // at the first fully-fast pair (t=10s→11s at 12 m/s).
      final pts = <LocationPointEntity>[];
      var t = 0;
      var d = 0.0;
      for (var i = 0; i < 10; i++) {
        pts.add(_pt(_lngDelta(d), t));
        d += 5.0;
        t += 1000;
      }
      for (var i = 0; i <= 12; i++) {
        pts.add(_pt(_lngDelta(d), t));
        d += 12.0;
        t += 1000;
      }
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.startMs, 10000); // first fast pair's prev.ts
    });

    test('exactly at threshold speed (11.5) does not flag', () {
      // Exactly 11.5 m/s for 15s — not above threshold
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 15; i++) {
        pts.add(_pt(_lngDelta(11.5 * i), i * 1000));
      }
      expect(detect(pts), isEmpty);
    });

    test('just above threshold (11.6 m/s) for 10s flags', () {
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 10; i++) {
        pts.add(_pt(_lngDelta(11.6 * i), i * 1000));
      }
      final result = detect(pts);
      expect(result, hasLength(1));
    });

    test('zero-delta timestamps are skipped gracefully', () {
      final pts = [
        _pt(0, 1000),
        _pt(_lngDelta(50), 1000), // same timestamp
        _pt(_lngDelta(100), 2000),
      ];
      // Should not crash; zero-dt pair skipped
      expect(detect(pts), isEmpty);
    });

    test('custom thresholds work', () {
      // 6 m/s for 6s — normally fine, but with maxSpeed=5 and window=5s → flag
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 6; i++) {
        pts.add(_pt(_lngDelta(6.0 * i), i * 1000));
      }
      final result = detect(pts, maxSpeedMps: 5.0, minWindowMs: 5000);
      expect(result, hasLength(1));
    });

    test('realistic run at 4:30/km pace is clean', () {
      // 4:30/km = 270 s/km = 3.70 m/s — well below threshold
      final pts = <LocationPointEntity>[];
      const speedMps = 3.70;
      for (var i = 0; i <= 600; i += 5) {
        pts.add(_pt(_lngDelta(speedMps * i), i * 1000));
      }
      expect(detect(pts), isEmpty);
    });

    test('SpeedViolation avgSpeedMps is accurate', () {
      // 20 m/s for 10s → avg should be ~20 m/s
      final pts = <LocationPointEntity>[];
      for (var i = 0; i <= 10; i++) {
        pts.add(_pt(_lngDelta(20.0 * i), i * 1000));
      }
      final result = detect(pts);
      expect(result, hasLength(1));
      expect(result.first.avgSpeedMps, closeTo(20.0, 0.5));
    });
  });
}
