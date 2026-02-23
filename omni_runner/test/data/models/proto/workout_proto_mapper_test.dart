import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/data/models/isar/workout_session_record.dart';
import 'package:omni_runner/data/models/proto/workout_proto_mapper.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

void main() {
  group('WorkoutProtoMapper — pointsToBytes', () {
    test('empty list returns empty JSON array bytes', () {
      final bytes = WorkoutProtoMapper.pointsToBytes([]);
      expect(utf8.decode(bytes), equals('[]'));
    });

    test('single point with all fields serialises correctly', () {
      const point = LocationPointEntity(
        lat: -23.550520,
        lng: -46.633308,
        alt: 760.0,
        accuracy: 5.2,
        speed: 3.1,
        bearing: 180.0,
        timestampMs: 1707753600000,
      );
      final bytes = WorkoutProtoMapper.pointsToBytes([point]);
      final decoded = jsonDecode(utf8.decode(bytes)) as List;
      expect(decoded, hasLength(1));
      final m = decoded.first as Map<String, dynamic>;
      expect(m['lat'], -23.550520);
      expect(m['lng'], -46.633308);
      expect(m['alt'], 760.0);
      expect(m['accuracy'], 5.2);
      expect(m['speed'], 3.1);
      expect(m['bearing'], 180.0);
      expect(m['timestampMs'], 1707753600000);
    });

    test('null optional fields are omitted from output', () {
      const point = LocationPointEntity(
        lat: -23.55,
        lng: -46.63,
        timestampMs: 1000,
      );
      final bytes = WorkoutProtoMapper.pointsToBytes([point]);
      final decoded = jsonDecode(utf8.decode(bytes)) as List;
      final m = decoded.first as Map<String, dynamic>;
      expect(m.containsKey('alt'), isFalse);
      expect(m.containsKey('accuracy'), isFalse);
      expect(m.containsKey('speed'), isFalse);
      expect(m.containsKey('bearing'), isFalse);
      expect(m.keys, unorderedEquals(['lat', 'lng', 'timestampMs']));
    });

    test('multiple points preserve order', () {
      final points = List.generate(
        3,
        (i) => LocationPointEntity(
          lat: -23.0 + i * 0.001,
          lng: -46.0 + i * 0.001,
          timestampMs: 1000 + i * 1000,
        ),
      );
      final bytes = WorkoutProtoMapper.pointsToBytes(points);
      final decoded = jsonDecode(utf8.decode(bytes)) as List;
      expect(decoded, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final m = decoded[i] as Map<String, dynamic>;
        expect(m['timestampMs'], 1000 + i * 1000);
      }
    });

    test('bytes are non-empty for non-empty points', () {
      const point = LocationPointEntity(
        lat: 0,
        lng: 0,
        timestampMs: 0,
      );
      final bytes = WorkoutProtoMapper.pointsToBytes([point]);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(2)); // More than '[]'
    });

    test('timestampMs is serialised as int64', () {
      const bigTs = 9999999999999; // > 2^32
      const point = LocationPointEntity(
        lat: 0,
        lng: 0,
        timestampMs: bigTs,
      );
      final json = WorkoutProtoMapper.pointsToJson([point]);
      final decoded = jsonDecode(json) as List;
      expect((decoded.first as Map)['timestampMs'], bigTs);
    });
  });

  group('WorkoutProtoMapper — pointsToJson', () {
    test('returns valid JSON string', () {
      const point = LocationPointEntity(
        lat: 1.0,
        lng: 2.0,
        timestampMs: 500,
      );
      final json = WorkoutProtoMapper.pointsToJson([point]);
      expect(() => jsonDecode(json), returnsNormally);
    });
  });

  group('WorkoutProtoMapper — sessionToPayload', () {
    late WorkoutSessionRecord record;

    setUp(() {
      record = WorkoutSessionRecord()
        ..sessionUuid = 'abc-123'
        ..userId = 'user-1'
        ..status = 3
        ..startTimeMs = 1000
        ..endTimeMs = 2000
        ..totalDistanceM = 5230.5
        ..movingMs = 1800000
        ..isVerified = true
        ..isSynced = false
        ..ghostSessionId = 'ghost-1'
        ..integrityFlags = [];
    });

    test('contains all required fields', () {
      final payload = WorkoutProtoMapper.sessionToPayload(
        record: record,
        userId: 'uid-42',
        pointsPath: 'uid-42/abc-123.json',
      );
      expect(payload['id'], 'abc-123');
      expect(payload['user_id'], 'uid-42');
      expect(payload['status'], 3);
      expect(payload['start_time_ms'], 1000);
      expect(payload['end_time_ms'], 2000);
      expect(payload['total_distance_m'], 5230.5);
      expect(payload['moving_ms'], 1800000);
      expect(payload['is_verified'], true);
      expect(payload['integrity_flags'], isEmpty);
      expect(payload['ghost_session_id'], 'ghost-1');
      expect(payload['points_path'], 'uid-42/abc-123.json');
    });

    test('nullable endTimeMs is passed through', () {
      record.endTimeMs = null;
      final payload = WorkoutProtoMapper.sessionToPayload(
        record: record,
        userId: 'u',
        pointsPath: 'p',
      );
      expect(payload['end_time_ms'], isNull);
    });

    test('integrity flags are included', () {
      record.isVerified = false;
      record.integrityFlags = ['HIGH_SPEED', 'TELEPORT'];
      final payload = WorkoutProtoMapper.sessionToPayload(
        record: record,
        userId: 'u',
        pointsPath: 'p',
      );
      expect(payload['is_verified'], false);
      expect(payload['integrity_flags'], ['HIGH_SPEED', 'TELEPORT']);
    });

    test('does not contain isSynced (local-only field)', () {
      final payload = WorkoutProtoMapper.sessionToPayload(
        record: record,
        userId: 'u',
        pointsPath: 'p',
      );
      expect(payload.containsKey('isSynced'), isFalse);
      expect(payload.containsKey('is_synced'), isFalse);
    });
  });
}
