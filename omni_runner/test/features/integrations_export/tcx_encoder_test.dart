import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/features/integrations_export/data/tcx/tcx_encoder.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

void main() {
  const encoder = TcxEncoder();

  WorkoutSessionEntity makeSession({
    String id = 'test-tcx',
    int startMs = 1708160400000,
    int endMs = 1708164000000,
    double distanceM = 10000.0,
    int? avgBpm = 145,
    int? maxBpm = 175,
  }) {
    return WorkoutSessionEntity(
      id: id,
      status: WorkoutStatus.completed,
      startTimeMs: startMs,
      endTimeMs: endMs,
      totalDistanceM: distanceM,
      route: const [],
      avgBpm: avgBpm,
      maxBpm: maxBpm,
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

  group('TcxEncoder', () {
    test('produces valid XML with TCX namespace', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(
        xml,
        contains('TrainingCenterDatabase'),
      );
      expect(
        xml,
        contains(
          'xmlns="http://www.garmin.com/xmlschemas/'
          'TrainingCenterDatabase/v2"',
        ),
      );
    });

    test('includes Activity with Sport="Running"', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<Activity Sport="Running">'));
      expect(xml, contains('</Activity>'));
    });

    test('includes Lap with total time and distance', () {
      final session = makeSession(
        startMs: 1708160400000,
        endMs: 1708164000000, // 3600s = 1hr
        distanceM: 10000.0,
      );

      final bytes = encoder.encode(
        session: session,
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<TotalTimeSeconds>3600.0</TotalTimeSeconds>'));
      expect(xml, contains('<DistanceMeters>10000.0</DistanceMeters>'));
    });

    test('includes average and max HR in Lap', () {
      final bytes = encoder.encode(
        session: makeSession(avgBpm: 145, maxBpm: 175),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<AverageHeartRateBpm>'));
      expect(xml, contains('<Value>145</Value>'));
      expect(xml, contains('<MaximumHeartRateBpm>'));
      expect(xml, contains('<Value>175</Value>'));
    });

    test('omits HR in Lap when null', () {
      final bytes = encoder.encode(
        session: makeSession(avgBpm: null, maxBpm: null),
        route: makeRoute(),
      );

      final xml = utf8.decode(bytes);

      expect(xml, isNot(contains('AverageHeartRateBpm')));
      expect(xml, isNot(contains('MaximumHeartRateBpm')));
    });

    test('includes all Trackpoints with position, altitude, distance', () {
      final route = makeRoute(count: 3);
      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<LatitudeDegrees>-23.55000000</LatitudeDegrees>'));
      expect(
        xml,
        contains('<LongitudeDegrees>-46.63000000</LongitudeDegrees>'),
      );
      expect(xml, contains('<AltitudeMeters>760.0</AltitudeMeters>'));

      // Should have 3 trackpoints
      expect(
        RegExp('<Trackpoint>').allMatches(xml).length,
        equals(3),
      );
    });

    test('accumulates distance across trackpoints', () {
      final route = makeRoute(count: 3);
      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
      );

      final xml = utf8.decode(bytes);

      // First point should have 0 distance
      final distanceMatches = RegExp(
        r'<DistanceMeters>([\d.]+)</DistanceMeters>',
      ).allMatches(xml);

      // 1 in Lap + 3 in Trackpoints = 4 total
      final trackpointDistances = distanceMatches.skip(1).toList();
      expect(trackpointDistances, hasLength(3));

      final firstDist =
          double.parse(trackpointDistances.first.group(1)!);
      final lastDist =
          double.parse(trackpointDistances.last.group(1)!);

      expect(firstDist, equals(0.0));
      expect(lastDist, greaterThan(0.0));
    });

    test('includes HR in trackpoints when samples provided', () {
      final route = makeRoute(count: 2);
      final hr = makeHr(count: 2);

      final bytes = encoder.encode(
        session: makeSession(),
        route: route,
        hrSamples: hr,
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<HeartRateBpm>'));
      // Trackpoint-level HR values
      final hrMatches = RegExp(
        r'<HeartRateBpm>\s*<Value>(\d+)</Value>',
      ).allMatches(xml);

      // 2 in trackpoints + 1 avg + 1 max in Lap = find at least 2 in Track
      final bpms = hrMatches.map((m) => int.parse(m.group(1)!)).toList();
      expect(bpms, contains(140));
      expect(bpms, contains(145));
    });

    test('produces empty Track for empty route', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: const [],
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<Track>'));
      expect(xml, contains('</Track>'));
      expect(xml, isNot(contains('<Trackpoint>')));
    });

    test('includes Creator device name', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: const [],
      );

      final xml = utf8.decode(bytes);

      expect(xml, contains('<Creator xsi:type="Device_t">'));
      expect(xml, contains('<Name>Omni Runner</Name>'));
    });

    test('escapes XML special characters in notes', () {
      final bytes = encoder.encode(
        session: makeSession(),
        route: const [],
        activityName: 'Run <5k> & "fast"',
      );

      final xml = utf8.decode(bytes);

      expect(
        xml,
        contains('<Notes>Run &lt;5k&gt; &amp; &quot;fast&quot;</Notes>'),
      );
    });
  });
}
