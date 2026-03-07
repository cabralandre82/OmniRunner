import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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

}
