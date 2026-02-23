import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';

LocationPointEntity _pt(double lat, double lng, int ms) {
  return LocationPointEntity(lat: lat, lng: lng, timestampMs: ms);
}

void main() {
  late CalculatePace calculatePace;

  setUp(() {
    calculatePace = const CalculatePace();
  });

  group('CalculatePace', () {
    test('empty list returns null', () {
      expect(calculatePace([]), isNull);
    });

    test('single point returns null', () {
      expect(calculatePace([_pt(0, 0, 0)]), isNull);
    });

    test('two points with valid movement returns pace', () {
      // 0.001 deg lat ≈ 111.195m, 30s → 269.796 sec/km
      final points = [_pt(0.0, 0.0, 0), _pt(0.001, 0.0, 30000)];
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(269.7964817756191, 1e-6));
    });

    test('steady pace produces stable EMA output', () {
      // 5 identical segments → EMA converges to segment pace.
      final points = List.generate(
        6,
        (i) => _pt(i * 0.001, 0.0, i * 30000),
      );
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(269.7964817756191, 1e-6));
    });

    test('EMA smooths a sudden speed change', () {
      // Segments: ~270, ~270, ~270, ~540 sec/km
      // EMA final: 0.3*539.59 + 0.7*269.80 = 350.735
      final points = [
        _pt(0.0, 0.0, 0),
        _pt(0.001, 0.0, 30000),
        _pt(0.002, 0.0, 60000),
        _pt(0.003, 0.0, 90000),
        _pt(0.004, 0.0, 150000),
      ];
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(350.7354263083048, 1e-6));
    });

    test('segment with zero time is skipped', () {
      final points = [
        _pt(0.0, 0.0, 1000),
        _pt(0.001, 0.0, 1000), // zero delta → skip
        _pt(0.002, 0.0, 31000), // valid 30s
      ];
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(269.7964817756191, 1e-6));
    });

    test('segment with negative time is skipped', () {
      final points = [
        _pt(0.0, 0.0, 50000),
        _pt(0.001, 0.0, 40000), // backwards → skip
        _pt(0.002, 0.0, 80000), // valid: 40s, ~111m → 359.73 sec/km
      ];
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(359.7286423674921, 1e-6));
    });

    test('segment below minSegmentMeters is skipped', () {
      // ~1m movement (below 3m default threshold)
      final points = [_pt(0.0, 0.0, 0), _pt(0.000009, 0.0, 5000)];
      expect(calculatePace(points), isNull);
    });

    test('impossibly fast pace is rejected (below 100 sec/km)', () {
      // ~111m in 0.5s → ~4.5 sec/km (< 100)
      final points = [_pt(0.0, 0.0, 0), _pt(0.001, 0.0, 500)];
      expect(calculatePace(points), isNull);
    });

    test('impossibly slow pace is rejected (above 1800 sec/km)', () {
      // ~111m in 300s → ~2698 sec/km (> 1800)
      final points = [_pt(0.0, 0.0, 0), _pt(0.001, 0.0, 300000)];
      expect(calculatePace(points), isNull);
    });

    test('mixed valid and invalid segments returns smoothed valid', () {
      final points = [
        _pt(0.0, 0.0, 0),
        _pt(0.000009, 0.0, 1000), // too short → skip
        _pt(0.001, 0.0, 30000), // valid → EMA seed
        _pt(0.002, 0.0, 60000), // valid → EMA update
      ];
      final result = calculatePace(points);
      expect(result, isNotNull);
      // seg2: 263.17, seg3: 269.80 → EMA 0.3*269.80+0.7*263.17 = 265.16
      expect(result, closeTo(265.15921294994337, 1e-6));
    });

    test('all segments invalid returns null', () {
      final points = [
        _pt(0.0, 0.0, 0),
        _pt(0.000009, 0.0, 5000), // too short
        _pt(0.000018, 0.0, 10000), // too short
      ];
      expect(calculatePace(points), isNull);
    });

    test('custom alpha=1.0 uses only latest segment', () {
      const noSmooth = CalculatePace(alpha: 1.0);
      final points = [
        _pt(0.0, 0.0, 0),
        _pt(0.001, 0.0, 30000), // ~270
        _pt(0.002, 0.0, 90000), // ~540
      ];
      // alpha=1.0: final = latest = 539.59
      expect(noSmooth(points), closeTo(539.5929635512382, 1e-6));
    });

    test('custom alpha=0.0 keeps only first value', () {
      const allSmooth = CalculatePace(alpha: 0.0);
      final points = [
        _pt(0.0, 0.0, 0),
        _pt(0.001, 0.0, 30000), // ~270
        _pt(0.002, 0.0, 90000), // ~540
      ];
      // alpha=0.0: final = first = 269.80
      expect(allSmooth(points), closeTo(269.7964817756191, 1e-6));
    });

    test('typical 5K run pace (~5:00/km = 300 sec/km)', () {
      // ~100m segments in 30s each → 299.77 sec/km
      final points = List.generate(
        51,
        (i) => _pt(i * 0.0009, 0.0, i * 30000),
      );
      final result = calculatePace(points);
      expect(result, isNotNull);
      expect(result, closeTo(299.7738686395769, 1e-4));
    });
  });
}
