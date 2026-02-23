import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/integrity_detect_vehicle.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a GPS point that is [distanceDeg] degrees north of the previous.
/// At the equator, 1 degree ≈ 111 km, so 0.001 ≈ 111 m.
LocationPointEntity _point(int timestampMs, double lat, double lng) =>
    LocationPointEntity(
      timestampMs: timestampMs,
      lat: lat,
      lng: lng,
      speed: 0,
      accuracy: 5,
    );

/// Generate a series of GPS points simulating constant speed travel.
///
/// At the equator: 0.001° lat ≈ 111 m.
/// If we space 0.001° per 5s → ~22.2 m/s (~80 km/h) — well above threshold.
List<LocationPointEntity> _vehiclePoints({
  required int startMs,
  required int count,
  required int intervalMs,
  double startLat = 0.0,
  double lng = 0.0,
  double latStepDeg = 0.001,
}) {
  final pts = <LocationPointEntity>[];
  for (var i = 0; i < count; i++) {
    pts.add(_point(
      startMs + i * intervalMs,
      startLat + i * latStepDeg,
      lng,
    ));
  }
  return pts;
}

/// Low-cadence step samples (e.g., phone in car — 0 SPM).
List<StepSample> _lowCadence({
  required int startMs,
  required int count,
  required int intervalMs,
  double spm = 0.0,
}) {
  final samples = <StepSample>[];
  for (var i = 0; i < count; i++) {
    samples.add(StepSample(
      timestampMs: startMs + i * intervalMs,
      spm: spm,
    ));
  }
  return samples;
}

/// Normal running cadence (170–180 SPM).
List<StepSample> _highCadence({
  required int startMs,
  required int count,
  required int intervalMs,
  double spm = 175.0,
}) =>
    _lowCadence(
      startMs: startMs,
      count: count,
      intervalMs: intervalMs,
      spm: spm,
    );

// ---------------------------------------------------------------------------
// Tests: IntegrityDetectVehicle (batch)
// ---------------------------------------------------------------------------

void main() {
  const detector = IntegrityDetectVehicle();

  group('IntegrityDetectVehicle (batch)', () {
    test('returns empty list when steps is null', () {
      final pts = _vehiclePoints(startMs: 0, count: 10, intervalMs: 5000);
      expect(detector.call(pts, steps: null), isEmpty);
    });

    test('returns empty list when steps is empty', () {
      final pts = _vehiclePoints(startMs: 0, count: 10, intervalMs: 5000);
      expect(detector.call(pts, steps: const []), isEmpty);
    });

    test('returns empty list when fewer than 2 GPS points', () {
      final pts = [_point(0, 0, 0)];
      final steps = _lowCadence(startMs: 0, count: 5, intervalMs: 5000);
      expect(detector.call(pts, steps: steps), isEmpty);
    });

    test('flags violation when high speed + low cadence for >= 30s', () {
      // 8 points spaced 5s apart → 35s total, lat step 0.001° ≈ 111m per 5s ≈ 22 m/s
      final pts = _vehiclePoints(startMs: 0, count: 8, intervalMs: 5000);
      // Low cadence at every second
      final steps = _lowCadence(startMs: 0, count: 40, intervalMs: 1000, spm: 5);
      final violations = detector.call(pts, steps: steps);
      expect(violations, isNotEmpty);
      expect(violations.first.avgSpm, lessThan(140));
      expect(violations.first.avgSpeedMps, greaterThan(4.2));
    });

    test('no violation when cadence is high (legitimate running)', () {
      final pts = _vehiclePoints(
        startMs: 0,
        count: 8,
        intervalMs: 5000,
        latStepDeg: 0.0003, // ≈ 33.3m per 5s ≈ 6.6 m/s (fast runner)
      );
      final steps = _highCadence(startMs: 0, count: 40, intervalMs: 1000, spm: 175);
      final violations = detector.call(pts, steps: steps);
      expect(violations, isEmpty);
    });

    test('no violation when speed is below threshold', () {
      // Very small lat step → slow speed (below 4.2 m/s)
      final pts = _vehiclePoints(
        startMs: 0,
        count: 8,
        intervalMs: 5000,
        latStepDeg: 0.0001, // ≈ 11.1m per 5s ≈ 2.2 m/s (walking pace)
      );
      final steps = _lowCadence(startMs: 0, count: 40, intervalMs: 1000);
      final violations = detector.call(pts, steps: steps);
      expect(violations, isEmpty);
    });

    test('no violation when window is shorter than 30s', () {
      // Only 6 points spaced 5s apart → 25s total, not enough
      final pts = _vehiclePoints(startMs: 0, count: 6, intervalMs: 5000);
      final steps = _lowCadence(startMs: 0, count: 30, intervalMs: 1000);
      // Window duration = 25s < 30s default
      final violations = detector.call(pts, steps: steps);
      expect(violations, isEmpty);
    });

    test('window resets when cadence goes above threshold', () {
      // First 4 segments: vehicle-like (20s)
      final pts1 = _vehiclePoints(startMs: 0, count: 5, intervalMs: 5000);
      // Then 2 segments with normal cadence (breaks the window)
      // Then 4 more vehicle segments (20s) — still not enough
      final pts2 = _vehiclePoints(
        startMs: 25000,
        count: 5,
        intervalMs: 5000,
        startLat: 0.005,
      );
      final allPts = [...pts1, ...pts2];

      final steps = <StepSample>[
        // Low cadence for first 25s
        ..._lowCadence(startMs: 0, count: 25, intervalMs: 1000, spm: 5),
        // High cadence for next 5s (breaks window)
        ..._highCadence(startMs: 25000, count: 5, intervalMs: 1000, spm: 175),
        // Low cadence again
        ..._lowCadence(startMs: 30000, count: 20, intervalMs: 1000, spm: 5),
      ];

      final violations = detector.call(allPts, steps: steps);
      // Neither window reaches 30s due to the break
      expect(violations, isEmpty);
    });

    test('detects multiple separate violations', () {
      // First violation: 0–40s (8 segments at 5s each)
      final pts1 = _vehiclePoints(startMs: 0, count: 9, intervalMs: 5000);
      // Gap with normal cadence at 45s
      // Second violation: 50s–90s (8 segments at 5s each)
      final pts2 = _vehiclePoints(
        startMs: 50000,
        count: 9,
        intervalMs: 5000,
        startLat: 0.05,
      );

      final allPts = [...pts1, ...pts2];

      final steps = <StepSample>[
        ..._lowCadence(startMs: 0, count: 45, intervalMs: 1000, spm: 0),
        ..._highCadence(startMs: 45000, count: 5, intervalMs: 1000, spm: 175),
        ..._lowCadence(startMs: 50000, count: 45, intervalMs: 1000, spm: 0),
      ];

      final violations = detector.call(allPts, steps: steps);
      expect(violations.length, greaterThanOrEqualTo(2));
    });

    test('custom thresholds work correctly', () {
      final pts = _vehiclePoints(
        startMs: 0,
        count: 8,
        intervalMs: 5000,
        latStepDeg: 0.0002, // ≈ 22.2m per 5s ≈ 4.44 m/s (just above default)
      );
      final steps = _lowCadence(startMs: 0, count: 40, intervalMs: 1000, spm: 130);

      // With default thresholds, this should be flagged (speed > 4.2, cadence < 140)
      final violations = detector.call(pts, steps: steps);
      expect(violations, isNotEmpty);

      // With a higher speed threshold, should NOT be flagged
      final violations2 = detector.call(pts,
          steps: steps, minSpeedMps: 10.0);
      expect(violations2, isEmpty);

      // With a lower cadence threshold, should NOT be flagged
      final violations3 = detector.call(pts,
          steps: steps, maxCadenceSpm: 100.0);
      expect(violations3, isEmpty);
    });

    test('handles zero-duration GPS segments gracefully', () {
      final pts = [
        _point(1000, 0, 0),
        _point(1000, 0.001, 0), // same timestamp
        _point(6000, 0.002, 0),
      ];
      final steps = _lowCadence(startMs: 0, count: 10, intervalMs: 1000);
      // Should not crash
      expect(() => detector.call(pts, steps: steps), returnsNormally);
    });

    test('violation contains correct avg speed and avg spm', () {
      final pts = _vehiclePoints(startMs: 0, count: 8, intervalMs: 5000);
      final steps = _lowCadence(startMs: 0, count: 40, intervalMs: 1000, spm: 10);
      final violations = detector.call(pts, steps: steps);
      expect(violations, isNotEmpty);

      final v = violations.first;
      expect(v.avgSpeedMps, greaterThan(0));
      expect(v.avgSpm, closeTo(10.0, 1.0));
      expect(v.startMs, 0);
      expect(v.endMs, greaterThanOrEqualTo(30000));
    });

    test('flag constant is VEHICLE_SUSPECT', () {
      expect(IntegrityDetectVehicle.flag, 'VEHICLE_SUSPECT');
    });

    test('no steps in GPS interval returns null SPM → no violation', () {
      final pts = _vehiclePoints(startMs: 0, count: 8, intervalMs: 5000);
      // Steps only AFTER the GPS window
      final steps = _lowCadence(startMs: 100000, count: 5, intervalMs: 1000);
      final violations = detector.call(pts, steps: steps);
      expect(violations, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Tests: VehicleSlidingDetector (live/incremental)
  // -------------------------------------------------------------------------

  group('VehicleSlidingDetector', () {
    test('reset clears all data', () {
      final sd = VehicleSlidingDetector();
      sd.addPoint(_point(0, 0, 0));
      sd.addStepSample(const StepSample(timestampMs: 0, spm: 0));
      expect(sd.pointCount, 1);
      expect(sd.stepCount, 1);
      sd.reset();
      expect(sd.pointCount, 0);
      expect(sd.stepCount, 0);
    });

    test('returns empty when not enough points', () {
      final sd = VehicleSlidingDetector();
      sd.addPoint(_point(0, 0, 0));
      expect(sd.check(), isEmpty);
    });

    test('returns empty when check interval not met', () {
      final sd = VehicleSlidingDetector(checkIntervalMs: 10000);
      // Add enough points but trigger check twice quickly
      for (final p in _vehiclePoints(startMs: 0, count: 10, intervalMs: 5000)) {
        sd.addPoint(p);
      }
      for (final s in _lowCadence(startMs: 0, count: 50, intervalMs: 1000)) {
        sd.addStepSample(s);
      }
      // First check — should run
      final v1 = sd.check();
      // Second immediate check — should skip (interval not met)
      final v2 = sd.check();
      expect(v2, isEmpty);
      // v1 may or may not have violations depending on timing
      expect(v1, isA<List<VehicleViolation>>());
    });

    test('detects vehicle in sliding window', () {
      final sd = VehicleSlidingDetector(
        windowMs: 60000,
        checkIntervalMs: 0, // check every time
      );

      // Feed vehicle-like points over 40s
      for (final p in _vehiclePoints(startMs: 0, count: 9, intervalMs: 5000)) {
        sd.addPoint(p);
      }
      for (final s in _lowCadence(startMs: 0, count: 45, intervalMs: 1000, spm: 5)) {
        sd.addStepSample(s);
      }

      final violations = sd.check();
      expect(violations, isNotEmpty);
    });

    test('evicts old data outside the window', () {
      final sd = VehicleSlidingDetector(
        windowMs: 30000,
        checkIntervalMs: 0,
      );

      // Add old points that should be evicted
      sd.addPoint(_point(0, 0, 0));
      sd.addStepSample(const StepSample(timestampMs: 0, spm: 100));

      // Add current points at 100000ms (100s) — old data at 0ms is outside 30s window
      for (final p in _vehiclePoints(startMs: 100000, count: 3, intervalMs: 5000)) {
        sd.addPoint(p);
      }

      sd.check();
      // After check, old points should be evicted
      // pointCount should be 3 (the new ones), not 4
      expect(sd.pointCount, 3);
      expect(sd.stepCount, 0); // old step was evicted
    });

    test('returns empty when steps are empty', () {
      final sd = VehicleSlidingDetector(checkIntervalMs: 0);
      for (final p in _vehiclePoints(startMs: 0, count: 8, intervalMs: 5000)) {
        sd.addPoint(p);
      }
      // No step samples added
      final violations = sd.check();
      expect(violations, isEmpty);
    });

    test('pointCount and stepCount report correctly', () {
      final sd = VehicleSlidingDetector();
      expect(sd.pointCount, 0);
      expect(sd.stepCount, 0);

      sd.addPoint(_point(0, 0, 0));
      sd.addPoint(_point(1000, 0.001, 0));
      sd.addStepSample(const StepSample(timestampMs: 0, spm: 170));

      expect(sd.pointCount, 2);
      expect(sd.stepCount, 1);
    });

    test('custom thresholds are passed to inner detector', () {
      final sd = VehicleSlidingDetector(
        checkIntervalMs: 0,
        minSpeedMps: 100.0, // very high — nothing triggers
      );
      for (final p in _vehiclePoints(startMs: 0, count: 9, intervalMs: 5000)) {
        sd.addPoint(p);
      }
      for (final s in _lowCadence(startMs: 0, count: 45, intervalMs: 1000)) {
        sd.addStepSample(s);
      }
      expect(sd.check(), isEmpty);
    });
  });
}
