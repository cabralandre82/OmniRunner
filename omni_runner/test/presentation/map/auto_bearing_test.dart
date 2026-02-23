import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/map/auto_bearing.dart';

LocationPointEntity _pt({
  double lat = 0.0,
  double lng = 0.0,
  double? speed,
  double? bearing,
  int timestampMs = 0,
}) =>
    LocationPointEntity(
      lat: lat,
      lng: lng,
      speed: speed,
      bearing: bearing,
      timestampMs: timestampMs,
    );

void main() {
  group('AutoBearing.fromPoint', () {
    test('returns bearing when moving fast with valid bearing', () {
      expect(
        AutoBearing.fromPoint(_pt(speed: 3.0, bearing: 90.0), fallback: 0.0),
        90.0,
      );
    });

    test('returns fallback when speed is null', () {
      expect(
        AutoBearing.fromPoint(
          _pt(speed: null, bearing: 90.0),
          fallback: 45.0,
        ),
        45.0,
      );
    });

    test('returns fallback when speed is below threshold', () {
      expect(
        AutoBearing.fromPoint(_pt(speed: 0.5, bearing: 90.0), fallback: 45.0),
        45.0,
      );
    });

    test('returns fallback when speed equals threshold (<=)', () {
      expect(
        AutoBearing.fromPoint(_pt(speed: 1.0, bearing: 90.0), fallback: 45.0),
        45.0,
      );
    });

    test('returns fallback when bearing is null', () {
      expect(
        AutoBearing.fromPoint(
          _pt(speed: 3.0, bearing: null),
          fallback: 45.0,
        ),
        45.0,
      );
    });

    test('custom minSpeedMps is respected', () {
      final p = _pt(speed: 1.5, bearing: 180.0);
      // 1.5 > 1.0 default → bearing used
      expect(AutoBearing.fromPoint(p, fallback: 0.0), 180.0);
      // 1.5 <= 2.0 custom → fallback
      expect(
        AutoBearing.fromPoint(p, fallback: 0.0, minSpeedMps: 2.0),
        0.0,
      );
    });

    test('bearing 0 (north) is valid, not treated as null', () {
      expect(
        AutoBearing.fromPoint(_pt(speed: 3.0, bearing: 0.0), fallback: 90.0),
        0.0,
      );
    });

    test('bearing 359.9 is valid', () {
      expect(
        AutoBearing.fromPoint(
          _pt(speed: 3.0, bearing: 359.9),
          fallback: 0.0,
        ),
        359.9,
      );
    });
  });

  group('AutoBearing.fromTwoPoints', () {
    test('moving north returns ~0 degrees', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.001, lng: 0.0, timestampMs: 5000),
        fallback: 999.0,
      );
      expect(b, closeTo(0.0, 1.0));
    });

    test('moving east returns ~90 degrees', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.0, lng: 0.001, timestampMs: 5000),
        fallback: 999.0,
      );
      expect(b, closeTo(90.0, 1.0));
    });

    test('moving south returns ~180 degrees', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.001, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.0, lng: 0.0, timestampMs: 5000),
        fallback: 999.0,
      );
      expect(b, closeTo(180.0, 1.0));
    });

    test('moving west returns ~270 degrees', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.001, timestampMs: 0),
        _pt(lat: 0.0, lng: 0.0, timestampMs: 5000),
        fallback: 999.0,
      );
      expect(b, closeTo(270.0, 1.0));
    });

    test('returns fallback when points are too close', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.000001, lng: 0.0, timestampMs: 5000),
        fallback: 45.0,
      );
      expect(b, 45.0);
    });

    test('returns fallback when deltaMs is zero', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 1000),
        _pt(lat: 0.001, lng: 0.0, timestampMs: 1000),
        fallback: 45.0,
      );
      expect(b, 45.0);
    });

    test('returns fallback when deltaMs is negative', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 5000),
        _pt(lat: 0.001, lng: 0.0, timestampMs: 1000),
        fallback: 45.0,
      );
      expect(b, 45.0);
    });

    test('returns fallback when curr speed is below threshold', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.001, lng: 0.0, speed: 0.5, timestampMs: 5000),
        fallback: 45.0,
      );
      expect(b, 45.0);
    });

    test('calculates bearing when curr speed is null (no speed data)', () {
      final b = AutoBearing.fromTwoPoints(
        _pt(lat: 0.0, lng: 0.0, timestampMs: 0),
        _pt(lat: 0.001, lng: 0.0, timestampMs: 5000),
        fallback: 999.0,
      );
      expect(b, closeTo(0.0, 1.0));
    });
  });
}
