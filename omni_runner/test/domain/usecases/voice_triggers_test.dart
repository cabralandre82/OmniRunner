import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/usecases/voice_triggers.dart';

WorkoutMetricsEntity _m(double distM, {double? pace}) => WorkoutMetricsEntity(
      totalDistanceM: distM,
      elapsedMs: 0,
      movingMs: 0,
      currentPaceSecPerKm: pace,
      pointsCount: 0,
    );

void main() {
  late VoiceTriggers sut;

  setUp(() => sut = VoiceTriggers());

  group('KM trigger', () {
    test('no event at 0m', () {
      expect(sut.evaluate(_m(0)), isNull);
    });

    test('no event at 999m', () {
      expect(sut.evaluate(_m(999.9)), isNull);
    });

    test('fires at exactly 1000m', () {
      final event = sut.evaluate(_m(1000));
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.distanceAnnouncement);
      expect(event.payload['distanceKm'], 1.0);
      expect(event.priority, 10);
    });

    test('fires at 1001m (past 1km)', () {
      final event = sut.evaluate(_m(1001));
      expect(event, isNotNull);
      expect(event!.payload['distanceKm'], 1.0);
    });

    test('does not fire twice for same km', () {
      expect(sut.evaluate(_m(1000)), isNotNull);
      expect(sut.evaluate(_m(1050)), isNull);
      expect(sut.evaluate(_m(1999)), isNull);
    });

    test('fires again at 2km', () {
      expect(sut.evaluate(_m(1000)), isNotNull);
      expect(sut.evaluate(_m(1500)), isNull);
      final event = sut.evaluate(_m(2000));
      expect(event, isNotNull);
      expect(event!.payload['distanceKm'], 2.0);
    });

    test('fires for each km in sequence', () {
      for (var km = 1; km <= 5; km++) {
        final event = sut.evaluate(_m(km * 1000.0));
        expect(event, isNotNull, reason: 'should fire at ${km}km');
        expect(event!.payload['distanceKm'], km.toDouble());
      }
    });

    test('skipped km fires once for latest boundary', () {
      // Jump from 0 directly to 3.5 km
      final event = sut.evaluate(_m(3500));
      expect(event, isNotNull);
      expect(event!.payload['distanceKm'], 3.0);
      expect(sut.lastAnnouncedKm, 3);
    });

    test('includes pace when available', () {
      final event = sut.evaluate(_m(1000, pace: 330.0));
      expect(event, isNotNull);
      expect(event!.payload['paceFormatted'], '05:30');
      expect(event.payload['paceSecPerKm'], 330.0);
    });

    test('omits pace when null', () {
      final event = sut.evaluate(_m(1000));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
      expect(event.payload.containsKey('paceSecPerKm'), isFalse);
    });

    test('omits pace when zero', () {
      final event = sut.evaluate(_m(1000, pace: 0.0));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });

    test('omits pace when NaN', () {
      final event = sut.evaluate(_m(1000, pace: double.nan));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });

    test('omits pace when infinite', () {
      final event = sut.evaluate(_m(1000, pace: double.infinity));
      expect(event, isNotNull);
      expect(event!.payload.containsKey('paceFormatted'), isFalse);
    });

    test('pace formatting: 300 sec/km = 05:00', () {
      final event = sut.evaluate(_m(1000, pace: 300.0));
      expect(event!.payload['paceFormatted'], '05:00');
    });

    test('pace formatting: 270 sec/km = 04:30', () {
      final event = sut.evaluate(_m(1000, pace: 270.0));
      expect(event!.payload['paceFormatted'], '04:30');
    });

    test('pace formatting: 359.6 rounds to 360 = 06:00', () {
      final event = sut.evaluate(_m(1000, pace: 359.6));
      expect(event!.payload['paceFormatted'], '06:00');
    });
  });

  group('reset', () {
    test('reset allows re-announcing same km', () {
      expect(sut.evaluate(_m(1000)), isNotNull);
      expect(sut.evaluate(_m(1000)), isNull);
      sut.reset();
      expect(sut.lastAnnouncedKm, 0);
      expect(sut.evaluate(_m(1000)), isNotNull);
    });
  });

  group('custom interval', () {
    test('intervalM = 500 fires every 500m', () {
      final sut500 = VoiceTriggers(intervalM: 500);
      expect(sut500.evaluate(_m(499)), isNull);
      final e1 = sut500.evaluate(_m(500));
      expect(e1, isNotNull);
      expect(e1!.payload['distanceKm'], 0.5);
      expect(sut500.evaluate(_m(999)), isNull);
      final e2 = sut500.evaluate(_m(1000));
      expect(e2, isNotNull);
      expect(e2!.payload['distanceKm'], 1.0);
    });
  });

  group('synthetic run simulation', () {
    test('10km run fires 10 events at correct boundaries', () {
      var fired = 0;
      // Simulate distance increasing by ~100m each tick
      for (var d = 0.0; d <= 10000; d += 100) {
        final event = sut.evaluate(_m(d, pace: 330.0));
        if (event != null) {
          fired++;
          expect(event.payload['distanceKm'], fired.toDouble());
        }
      }
      expect(fired, 10);
      expect(sut.lastAnnouncedKm, 10);
    });
  });
}
