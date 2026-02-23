import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

void main() {
  group('WatchSessionPayload.tryParse', () {
    Map<String, dynamic> validSession() => {
          'version': 1,
          'source': 'apple_watch',
          'sessionId': 'abc-123',
          'startMs': 1000000,
          'endMs': 1060000,
          'totalDistanceM': 5123.4,
          'movingMs': 58000,
          'avgBpm': 142,
          'maxBpm': 175,
          'isVerified': true,
          'integrityFlags': <String>[],
          'points': [
            {
              'lat': -23.55,
              'lng': -46.63,
              'alt': 750.0,
              'accuracy': 4.0,
              'speed': 3.2,
              'timestampMs': 1000001,
            },
            {
              'lat': -23.551,
              'lng': -46.631,
              'alt': 751.0,
              'accuracy': 3.5,
              'speed': 3.1,
              'timestampMs': 1000002,
            },
          ],
          'hrSamples': [
            {'bpm': 140, 'timestampMs': 1000001},
            {'bpm': 145, 'timestampMs': 1000002},
          ],
        };

    test('parses a valid session', () {
      final payload = WatchSessionPayload.tryParse(validSession());

      expect(payload, isNotNull);
      expect(payload!.sessionId, 'abc-123');
      expect(payload.source, 'apple_watch');
      expect(payload.version, 1);
      expect(payload.startMs, 1000000);
      expect(payload.endMs, 1060000);
      expect(payload.totalDistanceM, 5123.4);
      expect(payload.movingMs, 58000);
      expect(payload.avgBpm, 142);
      expect(payload.maxBpm, 175);
      expect(payload.isVerified, true);
      expect(payload.integrityFlags, isEmpty);
      expect(payload.points, hasLength(2));
      expect(payload.hrSamples, hasLength(2));
    });

    test('GPS points are parsed correctly', () {
      final payload = WatchSessionPayload.tryParse(validSession())!;
      final p = payload.points.first;

      expect(p.lat, -23.55);
      expect(p.lng, -46.63);
      expect(p.alt, 750.0);
      expect(p.accuracy, 4.0);
      expect(p.speed, 3.2);
      expect(p.timestampMs, 1000001);
    });

    test('HR samples are parsed correctly', () {
      final payload = WatchSessionPayload.tryParse(validSession())!;
      final s = payload.hrSamples.first;

      expect(s.bpm, 140);
      expect(s.timestampMs, 1000001);
    });

    test('returns null when sessionId is missing', () {
      final json = validSession()..remove('sessionId');
      expect(WatchSessionPayload.tryParse(json), isNull);
    });

    test('returns null when sessionId is empty', () {
      final json = validSession()..['sessionId'] = '';
      expect(WatchSessionPayload.tryParse(json), isNull);
    });

    test('handles missing optional fields with defaults', () {
      final json = <String, dynamic>{
        'sessionId': 'minimal-session',
        'startMs': 1000,
        'endMs': 2000,
      };

      final payload = WatchSessionPayload.tryParse(json);

      expect(payload, isNotNull);
      expect(payload!.version, 1);
      expect(payload.source, 'unknown');
      expect(payload.totalDistanceM, 0.0);
      expect(payload.movingMs, 0);
      expect(payload.avgBpm, 0);
      expect(payload.maxBpm, 0);
      expect(payload.isVerified, true);
      expect(payload.integrityFlags, isEmpty);
      expect(payload.points, isEmpty);
      expect(payload.hrSamples, isEmpty);
    });

    test('handles numeric type coercion (double → int)', () {
      final json = validSession()
        ..['startMs'] = 1000000.0
        ..['avgBpm'] = 142.0;

      final payload = WatchSessionPayload.tryParse(json);

      expect(payload, isNotNull);
      expect(payload!.startMs, 1000000);
      expect(payload.avgBpm, 142);
    });

    test('handles numeric type coercion (int → double)', () {
      final json = validSession()..['totalDistanceM'] = 5000;

      final payload = WatchSessionPayload.tryParse(json);

      expect(payload, isNotNull);
      expect(payload!.totalDistanceM, 5000.0);
    });

    test('skips malformed GPS points', () {
      final json = validSession()
        ..['points'] = [
            {'lat': -23.55, 'lng': -46.63, 'timestampMs': 100},
            {'lat': null, 'lng': -46.63, 'timestampMs': 200},
            {'lat': -23.56, 'timestampMs': 300},
          ];

      final payload = WatchSessionPayload.tryParse(json);

      expect(payload, isNotNull);
      expect(payload!.points, hasLength(1));
      expect(payload.points.first.lat, -23.55);
    });

    test('skips malformed HR samples', () {
      final json = validSession()
        ..['hrSamples'] = [
            {'bpm': 140, 'timestampMs': 100},
            {'bpm': null, 'timestampMs': 200},
            {'timestampMs': 300},
          ];

      final payload = WatchSessionPayload.tryParse(json);

      expect(payload, isNotNull);
      expect(payload!.hrSamples, hasLength(1));
      expect(payload.hrSamples.first.bpm, 140);
    });

    test('convenience getters work', () {
      final payload = WatchSessionPayload.tryParse(validSession())!;

      expect(payload.duration, const Duration(milliseconds: 60000));
      expect(payload.movingDuration, const Duration(milliseconds: 58000));
      expect(payload.hasGps, true);
      expect(payload.hasHr, true);
    });

    test('Equatable comparison', () {
      final a = WatchSessionPayload.tryParse(validSession());
      final b = WatchSessionPayload.tryParse(validSession());

      expect(a, equals(b));
    });

    test('parses integrity flags', () {
      final json = validSession()
        ..['isVerified'] = false
        ..['integrityFlags'] = ['SPEED_EXCEEDED', 'TELEPORT_DETECTED'];

      final payload = WatchSessionPayload.tryParse(json)!;

      expect(payload.isVerified, false);
      expect(payload.integrityFlags, hasLength(2));
      expect(
        payload.integrityFlags,
        containsAll(['SPEED_EXCEEDED', 'TELEPORT_DETECTED']),
      );
    });
  });

  group('WatchLiveSample.tryParse', () {
    test('parses a valid live sample', () {
      final sample = WatchLiveSample.tryParse({
        'sessionId': 'sess-1',
        'bpm': 155,
        'pace': 320.5,
        'distanceM': 2500.0,
        'elapsedS': 600,
        'timestampMs': 1700000000,
      });

      expect(sample, isNotNull);
      expect(sample!.sessionId, 'sess-1');
      expect(sample.bpm, 155);
      expect(sample.paceSecondsPerKm, 320.5);
      expect(sample.distanceM, 2500.0);
      expect(sample.elapsedS, 600);
      expect(sample.timestampMs, 1700000000);
    });

    test('returns null when sessionId is missing', () {
      final sample = WatchLiveSample.tryParse({
        'bpm': 155,
        'pace': 320.5,
        'distanceM': 2500.0,
      });

      expect(sample, isNull);
    });

    test('handles numeric coercion', () {
      final sample = WatchLiveSample.tryParse({
        'sessionId': 's1',
        'bpm': 155.0,
        'pace': 320,
        'distanceM': 2500,
        'elapsedS': 600.0,
        'timestampMs': 1700000000.0,
      });

      expect(sample, isNotNull);
      expect(sample!.bpm, 155);
      expect(sample.paceSecondsPerKm, 320.0);
      expect(sample.distanceM, 2500.0);
      expect(sample.elapsedS, 600);
    });
  });

  group('WatchWorkoutState.tryParse', () {
    test('parses valid state', () {
      final state = WatchWorkoutState.tryParse({
        'sessionId': 'sess-1',
        'state': 'running',
        'timestampMs': 1700000000,
      });

      expect(state, isNotNull);
      expect(state!.sessionId, 'sess-1');
      expect(state.state, 'running');
      expect(state.isRunning, true);
      expect(state.isPaused, false);
      expect(state.isEnded, false);
    });

    test('convenience getters for paused and ended', () {
      expect(
        WatchWorkoutState.tryParse({
          'sessionId': 's',
          'state': 'paused',
          'timestampMs': 0,
        })!
            .isPaused,
        true,
      );

      expect(
        WatchWorkoutState.tryParse({
          'sessionId': 's',
          'state': 'ended',
          'timestampMs': 0,
        })!
            .isEnded,
        true,
      );
    });

    test('returns null when required fields missing', () {
      expect(
        WatchWorkoutState.tryParse({'sessionId': 's'}),
        isNull,
      );
      expect(
        WatchWorkoutState.tryParse({'state': 'running'}),
        isNull,
      );
    });
  });
}
