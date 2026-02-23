import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/features/integrations_export/data/gpx/gpx_encoder.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

void main() {
  const encoder = GpxEncoder();

  WorkoutSessionEntity makeSession({
    String id = 'test-gpx',
    int startMs = 1708160400000, // 2024-02-17 06:00:00 UTC
    int? endMs = 1708164000000, // 2024-02-17 07:00:00 UTC
    double? distanceM = 10000.0,
  }) {
    return WorkoutSessionEntity(
      id: id,
      status: WorkoutStatus.completed,
      startTimeMs: startMs,
      endTimeMs: endMs,
      totalDistanceM: distanceM,
      route: const [],
    );
  }

  List<LocationPointEntity> makeRoute({int count = 3}) {
    return List.generate(
      count,
      (i) => LocationPointEntity(
        lat: -23.55 + i * 0.001,
        lng: -46.63 + i * 0.001,
        alt: 760.0 + i,
        accuracy: 5.0,
        speed: 3.0,
        timestampMs: 1708160400000 + i * 10000,
      ),
    );
  }

  List<HeartRateSample> makeHr({int count = 3}) {
    return List.generate(
      count,
      (i) => HeartRateSample(
        bpm: 140 + i * 5,
        timestampMs: 1708160400000 + i * 10000,
      ),
    );
  }

  group('GpxEncoder', () {
    test('produces valid XML with GPX 1.1 header', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('version="1.1"'));
      expect(xml, contains('creator="Omni Runner"'));
      expect(xml, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
    });

    test('includes metadata with name and time', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: makeRoute(),
        activityName: 'Morning Run',
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<name>Morning Run</name>'));
      expect(xml, contains('<time>'));
      expect(xml, contains('2024-02-17'));
    });

    test('includes all trackpoints with lat/lon/ele/time', () {
      final route = makeRoute(count: 3);
      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('lat="-23.55000000"'));
      expect(xml, contains('lon="-46.63000000"'));
      expect(xml, contains('<ele>760.0</ele>'));
      expect(xml, contains('<trkseg>'));
      expect(xml, contains('</trkseg>'));

      // Should have 3 trackpoints
      expect(
        RegExp('<trkpt ').allMatches(xml).length,
        equals(3),
      );
    });

    test('includes HR data via Garmin extension when samples provided', () {
      final route = makeRoute(count: 2);
      final hr = makeHr(count: 2);

      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
        hrSamples: hr,
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('gpxtpx:TrackPointExtension'));
      expect(xml, contains('<gpxtpx:hr>140</gpxtpx:hr>'));
      expect(xml, contains('<gpxtpx:hr>145</gpxtpx:hr>'));
    });

    test('omits HR extension when no samples provided', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, isNot(contains('gpxtpx:hr')));
    });

    test('skips HR for trackpoints too far from any sample', () {
      final route = [
        const LocationPointEntity(
          lat: -23.55,
          lng: -46.63,
          timestampMs: 1708160400000,
        ),
        const LocationPointEntity(
          lat: -23.551,
          lng: -46.631,
          timestampMs: 1708160500000, // 100s later — far from HR sample
        ),
      ];

      // HR sample only at timestamp 0 — 100s gap to second point
      final hr = [
        const HeartRateSample(bpm: 150, timestampMs: 1708160400000),
      ];

      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
        hrSamples: hr,
      );

      final xml = utf8.decode(bytes);

      // First point should have HR
      expect(xml, contains('<gpxtpx:hr>150</gpxtpx:hr>'));

      // Only one HR extension (second point is 100s away, > 5s threshold)
      expect(
        RegExp('<gpxtpx:hr>').allMatches(xml).length,
        equals(1),
      );
    });

    test('produces empty trkseg for empty route', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: const [],
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<trkseg>'));
      expect(xml, contains('</trkseg>'));
      expect(xml, isNot(contains('<trkpt')));
    });

    test('escapes XML special characters in activity name', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: const [],
        activityName: 'Run <fast> & "hard"',
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('Run &lt;fast&gt; &amp; &quot;hard&quot;'));
      expect(xml, isNot(contains('Run <fast>')));
    });

    test('omits elevation when alt is null', () {
      final route = [
        const LocationPointEntity(
          lat: -23.55,
          lng: -46.63,
          timestampMs: 1708160400000,
        ),
      ];

      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
      );

      final xml = utf8.decode(bytes);

      expect(xml, isNot(contains('<ele>')));
    });
  });
}
