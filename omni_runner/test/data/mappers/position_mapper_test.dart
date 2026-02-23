import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:omni_runner/data/mappers/position_mapper.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

void main() {
  group('PositionMapper.fromPosition', () {
    test('maps all fields correctly from Position to LocationPointEntity', () {
      final timestamp = DateTime.utc(2026, 2, 12, 14, 30, 0);
      final position = geo.Position(
        latitude: -23.550520,
        longitude: -46.633308,
        altitude: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        heading: 180.0,
        timestamp: timestamp,
        altitudeAccuracy: 1.0,
        headingAccuracy: 2.0,
        speedAccuracy: 0.5,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result.lat, -23.550520);
      expect(result.lng, -46.633308);
      expect(result.alt, 760.0);
      expect(result.accuracy, 4.5);
      expect(result.speed, 3.2);
      expect(result.bearing, 180.0);
      expect(result.timestampMs, timestamp.millisecondsSinceEpoch);
    });

    test('timestampMs is positive for valid Position', () {
      final position = geo.Position(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        accuracy: 0.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.utc(2026, 2, 12),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result.timestampMs, isNot(0));
      expect(result.timestampMs, greaterThan(0));
    });

    test('maps zero values correctly (sea level, stationary, north)', () {
      final position = geo.Position(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        accuracy: 0.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.utc(2026, 6, 15, 8, 30),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result.lat, 0.0);
      expect(result.lng, 0.0);
      expect(result.alt, 0.0);
      expect(result.accuracy, 0.0);
      expect(result.speed, 0.0);
      expect(result.bearing, 0.0);
    });

    test('maps negative coordinates (southern/western hemispheres)', () {
      final position = geo.Position(
        latitude: -33.868820,
        longitude: -151.209296,
        altitude: 58.0,
        accuracy: 10.0,
        speed: 2.5,
        heading: 270.0,
        timestamp: DateTime.utc(2026, 3, 20, 14, 0),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result.lat, -33.868820);
      expect(result.lng, -151.209296);
    });

    test('preserves timestamp precision to millisecond', () {
      final timestamp = DateTime.utc(2026, 2, 12, 12, 30, 45, 123);
      final position = geo.Position(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        accuracy: 0.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: timestamp,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result.timestampMs, timestamp.millisecondsSinceEpoch);
      // Verify round-trip: epochMs → DateTime matches original
      final roundTrip = DateTime.fromMillisecondsSinceEpoch(
        result.timestampMs,
        isUtc: true,
      );
      expect(roundTrip.year, 2026);
      expect(roundTrip.month, 2);
      expect(roundTrip.day, 12);
      expect(roundTrip.millisecond, 123);
    });

    test('returns LocationPointEntity type', () {
      final position = geo.Position(
        latitude: 1.0,
        longitude: 2.0,
        altitude: 3.0,
        accuracy: 4.0,
        speed: 5.0,
        heading: 6.0,
        timestamp: DateTime.utc(2026),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      expect(result, isA<LocationPointEntity>());
    });

    test('two identical Positions produce equal entities', () {
      final timestamp = DateTime.utc(2026, 2, 12);
      final positionA = geo.Position(
        latitude: -23.550520,
        longitude: -46.633308,
        altitude: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        heading: 180.0,
        timestamp: timestamp,
        altitudeAccuracy: 1.0,
        headingAccuracy: 2.0,
        speedAccuracy: 0.5,
      );
      final positionB = geo.Position(
        latitude: -23.550520,
        longitude: -46.633308,
        altitude: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        heading: 180.0,
        timestamp: timestamp,
        altitudeAccuracy: 1.0,
        headingAccuracy: 2.0,
        speedAccuracy: 0.5,
      );

      final entityA = PositionMapper.fromPosition(positionA);
      final entityB = PositionMapper.fromPosition(positionB);

      expect(entityA, equals(entityB));
      expect(entityA.hashCode, equals(entityB.hashCode));
    });

    test('heading maps to bearing (field name translation)', () {
      final position = geo.Position(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        accuracy: 0.0,
        speed: 0.0,
        heading: 359.9,
        timestamp: DateTime.utc(2026),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      final result = PositionMapper.fromPosition(position);

      // geolocator calls it "heading", domain calls it "bearing"
      expect(result.bearing, 359.9);
    });
  });
}
