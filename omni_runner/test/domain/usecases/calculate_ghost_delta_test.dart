import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/calculate_ghost_delta.dart';

const _uc = CalculateGhostDelta();

LocationPointEntity _pt(double lat, double lng) =>
    LocationPointEntity(lat: lat, lng: lng, timestampMs: 0);

void main() {
  group('CalculateGhostDelta', () {
    test('returns null when runnerPos is null', () {
      final result = _uc(
        runnerPos: null,
        ghostPos: _pt(0.0, 0.0),
      );
      expect(result, isNull);
    });

    test('returns null when ghostPos is null', () {
      final result = _uc(
        runnerPos: _pt(0.0, 0.0),
        ghostPos: null,
      );
      expect(result, isNull);
    });

    test('returns null when both positions are null', () {
      final result = _uc(runnerPos: null, ghostPos: null);
      expect(result, isNull);
    });

    test('returns zero deltaM when positions are identical', () {
      final result = _uc(
        runnerPos: _pt(10.0, 20.0),
        ghostPos: _pt(10.0, 20.0),
      );
      expect(result, isNotNull);
      expect(result!.deltaM, 0.0);
    });

    test('returns positive deltaM (unsigned) without distance context', () {
      // ~111m apart (0.001 degree lat at equator)
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
      );
      expect(result, isNotNull);
      expect(result!.deltaM, greaterThan(100.0));
      expect(result.deltaM, lessThan(120.0));
    });

    test('unsigned delta is symmetric', () {
      final a = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
      );
      final b = _uc(
        runnerPos: _pt(0.0, 0.0),
        ghostPos: _pt(0.001, 0.0),
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.deltaM, closeTo(b!.deltaM, 0.001));
    });

    test('positive sign when runner distance > ghost distance', () {
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 500.0,
        ghostDistanceM: 400.0,
      );
      expect(result, isNotNull);
      expect(result!.deltaM, greaterThan(0.0));
    });

    test('negative sign when runner distance < ghost distance', () {
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 300.0,
        ghostDistanceM: 400.0,
      );
      expect(result, isNotNull);
      expect(result!.deltaM, lessThan(0.0));
    });

    test('positive sign when distances are equal', () {
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 400.0,
        ghostDistanceM: 400.0,
      );
      expect(result, isNotNull);
      expect(result!.deltaM, greaterThanOrEqualTo(0.0));
    });

    test('deltaM magnitude matches haversine regardless of sign', () {
      final ahead = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 500.0,
        ghostDistanceM: 400.0,
      );
      final behind = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 300.0,
        ghostDistanceM: 400.0,
      );
      expect(ahead, isNotNull);
      expect(behind, isNotNull);
      expect(ahead!.deltaM.abs(), closeTo(behind!.deltaM.abs(), 0.001));
    });

    test('deltaTimeMs is null by default', () {
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
      );
      expect(result, isNotNull);
      expect(result!.deltaTimeMs, isNull);
    });

    test('uses only runnerDistanceM for sign when ghostDistanceM is null', () {
      final result = _uc(
        runnerPos: _pt(0.001, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 500.0,
      );
      expect(result, isNotNull);
      // No sign info — unsigned positive
      expect(result!.deltaM, greaterThan(0.0));
    });

    test('same position with distances returns zero deltaM', () {
      final result = _uc(
        runnerPos: _pt(10.0, 20.0),
        ghostPos: _pt(10.0, 20.0),
        runnerDistanceM: 500.0,
        ghostDistanceM: 400.0,
      );
      expect(result, isNotNull);
      expect(result!.deltaM, 0.0);
    });

    test('realistic 50m gap with runner ahead', () {
      // ~50m apart (approx 0.00045 degrees lat)
      final result = _uc(
        runnerPos: _pt(0.00045, 0.0),
        ghostPos: _pt(0.0, 0.0),
        runnerDistanceM: 1050.0,
        ghostDistanceM: 1000.0,
      );
      expect(result, isNotNull);
      expect(result!.deltaM, greaterThan(40.0));
      expect(result.deltaM, lessThan(60.0));
    });
  });
}
