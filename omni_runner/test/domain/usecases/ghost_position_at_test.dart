import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/ghost_session_entity.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/ghost_position_at.dart';

const _uc = GhostPositionAt();

LocationPointEntity _pt(double lat, double lng, int ms) =>
    LocationPointEntity(lat: lat, lng: lng, timestampMs: ms);

GhostSessionEntity _ghost(List<LocationPointEntity> route) =>
    GhostSessionEntity(
      sessionId: 'g1',
      route: route,
      startTimeMs: route.isEmpty ? 0 : route.first.timestampMs,
      durationMs: route.length < 2
          ? 0
          : route.last.timestampMs - route.first.timestampMs,
    );

void main() {
  group('GhostPositionAt', () {
    test('returns null for empty route', () {
      final g = _ghost([]);
      expect(_uc(g, 0), isNull);
    });
    test('returns null for single-point route', () {
      final g = _ghost([_pt(10.0, 20.0, 1000)]);
      expect(_uc(g, 0), isNull);
    });
    test('clamps to first point when elapsedMs is 0', () {
      final g = _ghost([_pt(0.0, 0.0, 1000), _pt(1.0, 1.0, 2000)]);
      final r = _uc(g, 0)!;
      expect(r.lat, 0.0);
      expect(r.lng, 0.0);
    });
    test('clamps to first point when elapsedMs is negative', () {
      final g = _ghost([_pt(0.0, 0.0, 1000), _pt(1.0, 1.0, 2000)]);
      final r = _uc(g, -5000)!;
      expect(r.lat, 0.0);
      expect(r.lng, 0.0);
    });
    test('clamps to last point when elapsedMs exceeds duration', () {
      final g = _ghost([_pt(0.0, 0.0, 1000), _pt(1.0, 1.0, 2000)]);
      final r = _uc(g, 5000)!;
      expect(r.lat, 1.0);
      expect(r.lng, 1.0);
    });
    test('clamps to last point when elapsedMs equals duration', () {
      final g = _ghost([_pt(0.0, 0.0, 1000), _pt(1.0, 1.0, 2000)]);
      final r = _uc(g, 1000)!;
      expect(r.lat, 1.0);
      expect(r.lng, 1.0);
    });
    test('interpolates midpoint of two-point route', () {
      final g = _ghost([_pt(0.0, 0.0, 0), _pt(10.0, 20.0, 10000)]);
      final r = _uc(g, 5000)!;
      expect(r.lat, closeTo(5.0, 0.001));
      expect(r.lng, closeTo(10.0, 0.001));
      expect(r.timestampMs, 5000);
    });
    test('interpolates at 25% of two-point route', () {
      final g = _ghost([_pt(0.0, 0.0, 0), _pt(10.0, 20.0, 10000)]);
      final r = _uc(g, 2500)!;
      expect(r.lat, closeTo(2.5, 0.001));
      expect(r.lng, closeTo(5.0, 0.001));
    });
    test('interpolates at 75% of two-point route', () {
      final g = _ghost([_pt(0.0, 0.0, 0), _pt(10.0, 20.0, 10000)]);
      final r = _uc(g, 7500)!;
      expect(r.lat, closeTo(7.5, 0.001));
      expect(r.lng, closeTo(15.0, 0.001));
    });
    test('finds correct segment in multi-point route', () {
      // 4 segments: 0-10s, 10-20s, 20-30s, 30-40s
      final g = _ghost([
        _pt(0.0, 0.0, 0),
        _pt(10.0, 0.0, 10000),
        _pt(10.0, 10.0, 20000),
        _pt(20.0, 10.0, 30000),
        _pt(20.0, 20.0, 40000),
      ]);
      // 25s into run → segment [20s, 30s], 50% → lerp(10.0,20.0)=15.0
      final r = _uc(g, 25000)!;
      expect(r.lat, closeTo(15.0, 0.001));
      expect(r.lng, closeTo(10.0, 0.001));
    });
    test('interpolates within first segment of multi-point route', () {
      final g = _ghost([
        _pt(0.0, 0.0, 0),
        _pt(10.0, 10.0, 10000),
        _pt(20.0, 20.0, 20000),
      ]);
      final r = _uc(g, 5000)!;
      expect(r.lat, closeTo(5.0, 0.001));
      expect(r.lng, closeTo(5.0, 0.001));
    });
    test('interpolates within last segment of multi-point route', () {
      final g = _ghost([
        _pt(0.0, 0.0, 0),
        _pt(10.0, 10.0, 10000),
        _pt(20.0, 20.0, 20000),
      ]);
      final r = _uc(g, 15000)!;
      expect(r.lat, closeTo(15.0, 0.001));
      expect(r.lng, closeTo(15.0, 0.001));
    });
    test('exact point timestamp returns that point position', () {
      final g = _ghost([
        _pt(0.0, 0.0, 0),
        _pt(10.0, 10.0, 10000),
        _pt(20.0, 20.0, 20000),
      ]);
      // Exactly at 10s → boundary of segment [0,10s] at t=1.0
      final r = _uc(g, 10000)!;
      expect(r.lat, closeTo(10.0, 0.001));
      expect(r.lng, closeTo(10.0, 0.001));
    });
    test('works with realistic GPS coordinates', () {
      // ~111m apart in lat
      final g = _ghost([
        _pt(-23.5505, -46.6333, 0),
        _pt(-23.5495, -46.6333, 30000),
      ]);
      final r = _uc(g, 15000)!;
      expect(r.lat, closeTo(-23.5500, 0.0001));
      expect(r.lng, closeTo(-46.6333, 0.0001));
    });
    test('handles large route efficiently (binary search)', () {
      // 1000 points, 1s apart
      final pts = List.generate(
        1000,
        (i) => _pt(i * 0.001, i * 0.001, i * 1000),
      );
      final g = _ghost(pts);
      // 500.5s → between point 500 and 501
      final r = _uc(g, 500500)!;
      expect(r.lat, closeTo(0.5005, 0.001));
      expect(r.lng, closeTo(0.5005, 0.001));
    });
  });
}
