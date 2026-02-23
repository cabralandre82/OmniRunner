import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/auto_pause_detector.dart';

LocationPointEntity _pt(double lat, double lng, int ms, [double? spd]) {
  return LocationPointEntity(lat: lat, lng: lng, speed: spd, timestampMs: ms);
}

void main() {
  late AutoPauseDetector detector;

  setUp(() {
    detector = const AutoPauseDetector();
  });

  group('AutoPauseDetector', () {
    // ── Edge cases ──

    test('empty list returns no pause', () {
      final r = detector([]);
      expect(r.pauseSuggested, isFalse);
      expect(r.stationaryDurationMs, 0);
    });

    test('single point returns no pause', () {
      final r = detector([_pt(0, 0, 0)]);
      expect(r.pauseSuggested, isFalse);
      expect(r.stationaryDurationMs, 0);
    });

    // ── Running (no pause) ──

    test('runner moving fast does not trigger pause', () {
      // ~100m every 30s = 3.34 m/s (well above 0.5), no GPS speed field
      final pts = List.generate(
        6, (i) => _pt(i * 0.0009, 0.0, i * 30000),
      );
      expect(detector(pts).pauseSuggested, isFalse);
    });

    test('runner with GPS speed above threshold does not trigger', () {
      final pts = [
        _pt(0.0, 0.0, 0, 3.0),
        _pt(0.0, 0.0, 3000, 2.5),
        _pt(0.0, 0.0, 6000, 2.0),
      ];
      expect(detector(pts).pauseSuggested, isFalse);
    });

    // ── Stationary (pause suggested) ──

    test('stationary for 6s suggests pause', () {
      final pts = [
        _pt(0.0, 0.0, 0, 0.0),
        _pt(0.0, 0.0, 2000, 0.0),
        _pt(0.0, 0.0, 4000, 0.0),
        _pt(0.0, 0.0, 6000, 0.0),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isTrue);
      expect(r.stationaryDurationMs, 6000);
    });

    test('stationary for exactly 5s suggests pause', () {
      final pts = [_pt(0.0, 0.0, 0, 0.0), _pt(0.0, 0.0, 5000, 0.0)];
      final r = detector(pts);
      expect(r.pauseSuggested, isTrue);
      expect(r.stationaryDurationMs, 5000);
    });

    test('stationary for less than 5s does NOT suggest pause', () {
      final pts = [_pt(0.0, 0.0, 0, 0.0), _pt(0.0, 0.0, 4000, 0.0)];
      final r = detector(pts);
      expect(r.pauseSuggested, isFalse);
      expect(r.stationaryDurationMs, 4000);
    });

    // ── Speed threshold boundary ──

    test('speed exactly at 0.5 m/s does NOT trigger pause', () {
      final pts = [_pt(0.0, 0.0, 0, 0.5), _pt(0.0, 0.0, 6000, 0.5)];
      expect(detector(pts).pauseSuggested, isFalse);
    });

    test('speed at 0.49 m/s for 6s triggers pause', () {
      final pts = [_pt(0.0, 0.0, 0, 0.49), _pt(0.0, 0.0, 6000, 0.49)];
      expect(detector(pts).pauseSuggested, isTrue);
    });

    // ── Drift check ──

    test('low speed but significant drift does NOT trigger pause', () {
      // 0.0001 deg = 11.12m drift > 5m → runner genuinely moving
      final pts = [_pt(0.0, 0.0, 0, 0.1), _pt(0.0001, 0.0, 6000, 0.1)];
      expect(detector(pts).pauseSuggested, isFalse);
    });

    test('low speed with tiny drift triggers pause', () {
      // 0.000002 deg = 0.22m drift < 5m → GPS jitter, truly stationary
      final pts = [
        _pt(0.0, 0.0, 0, 0.1),
        _pt(0.000001, 0.0, 3000, 0.1),
        _pt(0.000002, 0.0, 6000, 0.1),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isTrue);
      expect(r.stationaryDurationMs, 6000);
    });

    // ── Transition: running then stopping ──

    test('running then stopping: pause after threshold', () {
      final pts = [
        _pt(0.0, 0.0, 0, 3.0),
        _pt(0.001, 0.0, 30000, 3.0),
        _pt(0.002, 0.0, 60000, 3.0),
        // Stopped (6 seconds)
        _pt(0.002, 0.0, 62000, 0.0),
        _pt(0.002, 0.0, 64000, 0.0),
        _pt(0.002, 0.0, 66000, 0.0),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isTrue);
      expect(r.stationaryDurationMs, 6000);
    });

    test('running then brief stop: no pause', () {
      final pts = [
        _pt(0.0, 0.0, 0, 3.0),
        _pt(0.001, 0.0, 30000, 3.0),
        _pt(0.001, 0.0, 31000, 0.0),
        _pt(0.001, 0.0, 33000, 0.0),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isFalse);
      expect(r.stationaryDurationMs, 3000);
    });

    // ── Calculated speed (no GPS speed field) ──

    test('uses calculated speed when GPS speed is null', () {
      // 0.000001 deg in 3s = 0.037 m/s (< 0.5), drift 0.22m (< 5m)
      final pts = [
        _pt(0.0, 0.0, 0),
        _pt(0.000001, 0.0, 3000),
        _pt(0.000002, 0.0, 6000),
      ];
      expect(detector(pts).pauseSuggested, isTrue);
    });

    // ── Custom thresholds ──

    test('custom thresholds are respected', () {
      const strict = AutoPauseDetector(
        minSpeedMps: 1.0,
        stationaryThresholdMs: 3000,
        maxDriftMeters: 2.0,
      );
      // 0.8 m/s < 1.0 threshold, 4s > 3s threshold
      final pts = [_pt(0.0, 0.0, 0, 0.8), _pt(0.0, 0.0, 4000, 0.8)];
      expect(strict(pts).pauseSuggested, isTrue);
    });

    // ── Resume detection ──

    test('stopped then resumed: no pause suggested', () {
      final pts = [
        _pt(0.0, 0.0, 0, 3.0),
        _pt(0.0, 0.0, 10000, 0.0),
        _pt(0.0, 0.0, 20000, 0.0),
        _pt(0.001, 0.0, 50000, 3.0),
        _pt(0.002, 0.0, 80000, 3.0),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isFalse);
      expect(r.stationaryDurationMs, 0);
    });

    // ── Zero/negative deltaMs ──

    test('segments with zero deltaMs are skipped', () {
      final pts = [
        _pt(0.0, 0.0, 0, 0.0),
        _pt(0.0, 0.0, 0, 0.0), // same timestamp
        _pt(0.0, 0.0, 6000, 0.0),
      ];
      final r = detector(pts);
      expect(r.pauseSuggested, isTrue);
      expect(r.stationaryDurationMs, 6000);
    });
  });
}
