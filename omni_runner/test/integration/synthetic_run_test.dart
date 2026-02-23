import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/auto_pause_detector.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';

/// Generates a straight-line run along latitude.
List<LocationPointEntity> _linearRun({
  required int segments,
  required double meters,
  required int ms,
  double startLat = 0.0,
  double accuracy = 5.0,
  int startMs = 0,
}) {
  const mPerDeg = 111194.93;
  final degPer = meters / mPerDeg;
  return List.generate(
    segments + 1,
    (i) => LocationPointEntity(
      lat: startLat + (i * degPer),
      lng: 0.0,
      accuracy: accuracy,
      speed: meters / (ms / 1000.0),
      timestampMs: startMs + (i * ms),
    ),
  );
}

LocationPointEntity _stopPt(LocationPointEntity ref, int offsetMs) {
  return LocationPointEntity(
    lat: ref.lat,
    lng: ref.lng,
    accuracy: 5.0,
    speed: 0.0,
    timestampMs: ref.timestampMs + offsetMs,
  );
}

void main() {
  const filter = FilterLocationPoints();
  const accumulate = AccumulateDistance();
  const pace = CalculatePace();
  const autoPause = AutoPauseDetector();

  group('Synthetic Run Integration', () {
    test('5K steady run: distance, pace, no auto-pause', () {
      // 50 × 100m in 30s = 5000m at 300 sec/km (5:00/km)
      final pts = _linearRun(segments: 50, meters: 100, ms: 30000);
      final filtered = filter(pts);
      expect(filtered.length, 51);
      expect(accumulate(filtered), closeTo(5000, 50));
      final p = pace(filtered);
      expect(p, isNotNull);
      expect(p, closeTo(300, 5));
      expect(autoPause(pts).pauseSuggested, isFalse);
    });

    test('1K fast run: distance and pace', () {
      // 20 × 50m in 10.5s = 1000m at 210 sec/km (3:30/km)
      final pts = _linearRun(segments: 20, meters: 50, ms: 10500);
      final filtered = filter(pts);
      expect(accumulate(filtered), closeTo(1000, 15));
      final p = pace(filtered);
      expect(p, isNotNull);
      expect(p, closeTo(210, 5));
    });

    test('slow jog: pace ≈ 480 sec/km (8:00/km)', () {
      // 30 × 50m in 24s
      final pts = _linearRun(segments: 30, meters: 50, ms: 24000);
      final filtered = filter(pts);
      final p = pace(filtered);
      expect(p, isNotNull);
      expect(p, closeTo(480, 10));
    });

    test('noisy GPS: bad accuracy points filtered out', () {
      final clean = _linearRun(segments: 20, meters: 100, ms: 30000);
      final noisy = <LocationPointEntity>[];
      for (var i = 0; i < clean.length; i++) {
        noisy.add(clean[i]);
        if (i % 4 == 2) {
          noisy.add(LocationPointEntity(
            lat: clean[i].lat + 0.01,
            lng: clean[i].lng,
            accuracy: 50.0,
            timestampMs: clean[i].timestampMs + 1000,
          ),);
        }
      }
      final filtered = filter(noisy);
      expect(filtered.length, 21);
      expect(accumulate(filtered), closeTo(2000, 30));
    });

    test('run then stop 10s: auto-pause detects stationary', () {
      final run = _linearRun(segments: 10, meters: 50, ms: 15000);
      final last = run.last;
      final all = [
        ...run,
        _stopPt(last, 3000),
        _stopPt(last, 7000),
        _stopPt(last, 10000),
      ];
      final result = autoPause(all);
      expect(result.pauseSuggested, isTrue);
      expect(result.stationaryDurationMs, 10000);
    });

    test('run then brief stop 4s: auto-pause does NOT trigger', () {
      final run = _linearRun(segments: 10, meters: 50, ms: 15000);
      final last = run.last;
      final all = [...run, _stopPt(last, 2000), _stopPt(last, 4000)];
      final result = autoPause(all);
      expect(result.pauseSuggested, isFalse);
      expect(result.stationaryDurationMs, 4000);
    });

    test('full pipeline: 10K consistent results', () {
      // 100 × 100m in 30s = 10,000m at 300 sec/km
      final pts = _linearRun(segments: 100, meters: 100, ms: 30000);
      final filtered = filter(pts);
      final distance = accumulate(filtered);
      final currentPace = pace(filtered);
      final pauseResult = autoPause(pts);
      expect(filtered.length, 101);
      expect(distance, closeTo(10000, 100));
      expect(currentPace, isNotNull);
      expect(currentPace, closeTo(300, 5));
      expect(pauseResult.pauseSuggested, isFalse);
      // Cross-check: avg pace from distance and elapsed time
      const totalTimeS = (100 * 30000) / 1000.0;
      final avgPace = totalTimeS / (distance / 1000.0);
      expect(avgPace, closeTo(300, 5));
    });

    test('very short run: 2 points, single segment', () {
      final pts = _linearRun(segments: 1, meters: 50, ms: 15000);
      final filtered = filter(pts);
      expect(filtered.length, 2);
      expect(accumulate(filtered), closeTo(50, 2));
      final p = pace(filtered);
      expect(p, isNotNull);
      expect(p, closeTo(300, 5));
    });
  });
}
