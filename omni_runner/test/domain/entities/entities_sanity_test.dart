import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';

void main() {
  group('LocationPointEntity', () {
    test('two instances with same values are equal (Equatable)', () {
      const a = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        alt: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        bearing: 180.0,
        timestampMs: 1704067200000,
      );

      const b = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        alt: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        bearing: 180.0,
        timestampMs: 1704067200000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different values are not equal', () {
      const a = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      const b = LocationPointEntity(
        lat: -23.550521,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      expect(a, isNot(equals(b)));
    });

    test('nullable fields default to null', () {
      const point = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      expect(point.alt, isNull);
      expect(point.accuracy, isNull);
      expect(point.speed, isNull);
      expect(point.bearing, isNull);
    });

    test('all fields are accessible and correct', () {
      const point = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        alt: 760.0,
        accuracy: 4.5,
        speed: 3.2,
        bearing: 180.0,
        timestampMs: 1704067200000,
      );

      expect(point.lat, -23.550520);
      expect(point.lng, -46.633308);
      expect(point.alt, 760.0);
      expect(point.accuracy, 4.5);
      expect(point.speed, 3.2);
      expect(point.bearing, 180.0);
      expect(point.timestampMs, 1704067200000);
    });
  });

  group('WorkoutSessionEntity', () {
    test('two instances with same values are equal (Equatable)', () {
      const route = <LocationPointEntity>[];

      const a = WorkoutSessionEntity(
        id: 'abc-123',
        userId: 'user-1',
        status: WorkoutStatus.completed,
        startTimeMs: 1704067200000,
        endTimeMs: 1704070800000,
        route: route,
      );

      const b = WorkoutSessionEntity(
        id: 'abc-123',
        userId: 'user-1',
        status: WorkoutStatus.completed,
        startTimeMs: 1704067200000,
        endTimeMs: 1704070800000,
        route: route,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different id are not equal', () {
      const route = <LocationPointEntity>[];

      const a = WorkoutSessionEntity(
        id: 'abc-123',
        status: WorkoutStatus.initial,
        startTimeMs: 1704067200000,
        route: route,
      );

      const b = WorkoutSessionEntity(
        id: 'xyz-789',
        status: WorkoutStatus.initial,
        startTimeMs: 1704067200000,
        route: route,
      );

      expect(a, isNot(equals(b)));
    });

    test('nullable fields default to null', () {
      const session = WorkoutSessionEntity(
        id: 'abc-123',
        status: WorkoutStatus.initial,
        startTimeMs: 1704067200000,
        route: [],
      );

      expect(session.userId, isNull);
      expect(session.endTimeMs, isNull);
    });

    test('all fields are accessible and correct', () {
      const point = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      const session = WorkoutSessionEntity(
        id: 'abc-123',
        userId: 'user-1',
        status: WorkoutStatus.running,
        startTimeMs: 1704067200000,
        endTimeMs: 1704070800000,
        route: [point],
      );

      expect(session.id, 'abc-123');
      expect(session.userId, 'user-1');
      expect(session.status, WorkoutStatus.running);
      expect(session.startTimeMs, 1704067200000);
      expect(session.endTimeMs, 1704070800000);
      expect(session.route, hasLength(1));
      expect(session.route.first, equals(point));
    });

    test('route with matching points produces equal sessions', () {
      const pointA = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      const pointB = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        timestampMs: 1704067200000,
      );

      const sessionA = WorkoutSessionEntity(
        id: 'abc-123',
        status: WorkoutStatus.completed,
        startTimeMs: 1704067200000,
        route: [pointA],
      );

      const sessionB = WorkoutSessionEntity(
        id: 'abc-123',
        status: WorkoutStatus.completed,
        startTimeMs: 1704067200000,
        route: [pointB],
      );

      expect(sessionA, equals(sessionB));
    });
  });

  group('WorkoutStatus', () {
    test('has exactly 5 values', () {
      expect(WorkoutStatus.values, hasLength(5));
      expect(
        WorkoutStatus.values,
        containsAll([
          WorkoutStatus.initial,
          WorkoutStatus.running,
          WorkoutStatus.paused,
          WorkoutStatus.completed,
          WorkoutStatus.discarded,
        ]),
      );
    });
  });
}
