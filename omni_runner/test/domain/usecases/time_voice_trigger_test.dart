import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/usecases/time_voice_trigger.dart';

WorkoutMetricsEntity _m(int movingMs, {double dist = 0, double? pace}) =>
    WorkoutMetricsEntity(
      totalDistanceM: dist,
      elapsedMs: movingMs,
      movingMs: movingMs,
      currentPaceSecPerKm: pace,
      pointsCount: 0,
    );

const kFiveMin = 300000;

void main() {
  late TimeVoiceTrigger sut;

  setUp(() => sut = TimeVoiceTrigger());

  group('basic interval', () {
    test('no event at 0 ms', () {
      expect(sut.evaluate(_m(0)), isNull);
    });

    test('no event at 4:59', () {
      expect(sut.evaluate(_m(kFiveMin - 1)), isNull);
    });

    test('fires at exactly 5 min', () {
      final event = sut.evaluate(_m(kFiveMin));
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.timeAnnouncement);
      expect(event.payload['elapsedMin'], 5);
      expect(event.priority, 12);
    });

    test('fires slightly past 5 min', () {
      final event = sut.evaluate(_m(kFiveMin + 500));
      expect(event, isNotNull);
      expect(event!.payload['elapsedMin'], 5);
    });

    test('does not fire twice for same interval', () {
      expect(sut.evaluate(_m(kFiveMin)), isNotNull);
      expect(sut.evaluate(_m(kFiveMin + 1000)), isNull);
      expect(sut.evaluate(_m(kFiveMin * 2 - 1)), isNull);
    });

    test('fires again at 10 min', () {
      expect(sut.evaluate(_m(kFiveMin)), isNotNull);
      final event = sut.evaluate(_m(kFiveMin * 2));
      expect(event, isNotNull);
      expect(event!.payload['elapsedMin'], 10);
    });

    test('fires for each interval in sequence', () {
      for (var i = 1; i <= 6; i++) {
        final event = sut.evaluate(_m(kFiveMin * i));
        expect(event, isNotNull, reason: 'should fire at ${i * 5} min');
        expect(event!.payload['elapsedMin'], i * 5);
      }
      expect(sut.lastAnnouncedInterval, 6);
    });
  });

  group('pause suppression', () {
    test('does not fire when paused even at boundary', () {
      expect(sut.evaluate(_m(kFiveMin), isPaused: true), isNull);
      expect(sut.lastAnnouncedInterval, 0);
    });

    test('fires on resume after boundary was crossed during pause', () {
      // Time reaches 5 min while paused
      expect(sut.evaluate(_m(kFiveMin), isPaused: true), isNull);
      // Resume — same moving time, not paused
      final event = sut.evaluate(_m(kFiveMin), isPaused: false);
      expect(event, isNotNull);
      expect(event!.payload['elapsedMin'], 5);
    });

    test('pause mid-interval does not lose progress', () {
      expect(sut.evaluate(_m(kFiveMin - 10000)), isNull); // 4:50
      expect(sut.evaluate(_m(kFiveMin - 5000), isPaused: true), isNull); // paused at 4:55
      final event = sut.evaluate(_m(kFiveMin)); // resume at 5:00
      expect(event, isNotNull);
    });
  });

  group('payload', () {
    test('includes distance in km', () {
      final event = sut.evaluate(_m(kFiveMin, dist: 1500.0));
      expect(event, isNotNull);
      expect(event!.payload['distanceKm'], 1.5);
    });

    test('distance is rounded to 2 decimal places', () {
      final event = sut.evaluate(_m(kFiveMin, dist: 1234.5));
      expect(event, isNotNull);
      // 1234.5 / 10 = 123.45, round = 123.0, / 100 = 1.23
      expect(event!.payload['distanceKm'], 1.23);
    });

    test('includes pace when available', () {
      final event = sut.evaluate(_m(kFiveMin, pace: 330.0));
      expect(event, isNotNull);
      expect(event!.payload['paceFormatted'], '05:30');
    });

    test('omits pace when null', () {
      final event = sut.evaluate(_m(kFiveMin));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });

    test('omits pace when zero', () {
      final event = sut.evaluate(_m(kFiveMin, pace: 0.0));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });

    test('omits pace when NaN', () {
      final event = sut.evaluate(_m(kFiveMin, pace: double.nan));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });
  });

  group('reset', () {
    test('reset allows re-announcing same interval', () {
      expect(sut.evaluate(_m(kFiveMin)), isNotNull);
      expect(sut.evaluate(_m(kFiveMin)), isNull);
      sut.reset();
      expect(sut.lastAnnouncedInterval, 0);
      expect(sut.evaluate(_m(kFiveMin)), isNotNull);
    });
  });

  group('custom interval', () {
    test('intervalMs = 60000 fires every minute', () {
      final sut1m = TimeVoiceTrigger(intervalMs: 60000);
      expect(sut1m.evaluate(_m(59999)), isNull);
      final e1 = sut1m.evaluate(_m(60000));
      expect(e1, isNotNull);
      expect(e1!.payload['elapsedMin'], 1);
      expect(sut1m.evaluate(_m(119999)), isNull);
      final e2 = sut1m.evaluate(_m(120000));
      expect(e2, isNotNull);
      expect(e2!.payload['elapsedMin'], 2);
    });

    test('intervalMs = 600000 fires every 10 min', () {
      final sut10m = TimeVoiceTrigger(intervalMs: 600000);
      expect(sut10m.evaluate(_m(kFiveMin)), isNull);
      final event = sut10m.evaluate(_m(600000));
      expect(event, isNotNull);
      expect(event!.payload['elapsedMin'], 10);
    });
  });

  group('skipped interval', () {
    test('jump from 0 to 15 min fires once for latest', () {
      final event = sut.evaluate(_m(kFiveMin * 3));
      expect(event, isNotNull);
      expect(event!.payload['elapsedMin'], 15);
      expect(sut.lastAnnouncedInterval, 3);
    });
  });

  group('synthetic run simulation', () {
    test('30 min run fires 6 events at correct boundaries', () {
      var fired = 0;
      // Simulate moving time increasing by 10 sec each tick
      for (var ms = 0; ms <= 1800000; ms += 10000) {
        final event = sut.evaluate(
          _m(ms, dist: ms * 0.003, pace: 330.0),
        );
        if (event != null) {
          fired++;
          expect(event.payload['elapsedMin'], fired * 5);
        }
      }
      expect(fired, 6);
    });
  });
}
