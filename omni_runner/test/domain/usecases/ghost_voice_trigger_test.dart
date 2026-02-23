import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/usecases/ghost_voice_trigger.dart';

void main() {
  late GhostVoiceTrigger sut;

  setUp(() => sut = GhostVoiceTrigger());

  group('null handling', () {
    test('null delta returns null', () {
      expect(sut.evaluate(null), isNull);
    });

    test('null delta does not change state', () {
      sut.evaluate(10.0); // set initial sign
      sut.evaluate(null);
      expect(sut.lastSign, 1);
    });
  });

  group('first observation', () {
    test('first positive delta records sign but does not fire', () {
      expect(sut.evaluate(20.0), isNull);
      expect(sut.lastSign, 1);
    });

    test('first negative delta records sign but does not fire', () {
      expect(sut.evaluate(-20.0), isNull);
      expect(sut.lastSign, -1);
    });
  });

  group('dead zone (hysteresis)', () {
    test('delta within dead zone returns null', () {
      expect(sut.evaluate(3.0), isNull);
      expect(sut.lastSign, 0);
    });

    test('negative delta within dead zone returns null', () {
      expect(sut.evaluate(-3.0), isNull);
      expect(sut.lastSign, 0);
    });

    test('exactly at minDeltaM boundary returns null', () {
      expect(sut.evaluate(5.0), isNull);
      expect(sut.lastSign, 0);
    });

    test('exactly at negative minDeltaM boundary returns null', () {
      expect(sut.evaluate(-5.0), isNull);
      expect(sut.lastSign, 0);
    });

    test('just above minDeltaM is accepted', () {
      expect(sut.evaluate(5.1), isNull); // first observation
      expect(sut.lastSign, 1);
    });
  });

  group('GHOST_PASSED — runner overtakes ghost', () {
    test('behind then ahead fires GHOST_PASSED', () {
      sut.evaluate(-10.0); // first: behind
      final event = sut.evaluate(10.0); // flip: ahead
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.custom);
      expect(event.payload['action'], 'GHOST_PASSED');
      expect(event.priority, 8);
    });

    test('same event not fired again while still ahead', () {
      sut.evaluate(-10.0);
      expect(sut.evaluate(10.0), isNotNull);
      expect(sut.evaluate(15.0), isNull);
      expect(sut.evaluate(20.0), isNull);
    });
  });

  group('GHOST_PASSED_BY — ghost overtakes runner', () {
    test('ahead then behind fires GHOST_PASSED_BY', () {
      sut.evaluate(10.0); // first: ahead
      final event = sut.evaluate(-10.0); // flip: behind
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.custom);
      expect(event.payload['action'], 'GHOST_PASSED_BY');
      expect(event.priority, 8);
    });

    test('same event not fired again while still behind', () {
      sut.evaluate(10.0);
      expect(sut.evaluate(-10.0), isNotNull);
      expect(sut.evaluate(-20.0), isNull);
      expect(sut.evaluate(-30.0), isNull);
    });
  });

  group('multiple flips', () {
    test('alternating flips fire correct events', () {
      sut.evaluate(-20.0); // init: behind
      final e1 = sut.evaluate(20.0); // -> ahead
      expect(e1!.payload['action'], 'GHOST_PASSED');

      final e2 = sut.evaluate(-20.0); // -> behind
      expect(e2!.payload['action'], 'GHOST_PASSED_BY');

      final e3 = sut.evaluate(20.0); // -> ahead again
      expect(e3!.payload['action'], 'GHOST_PASSED');
    });
  });

  group('dead zone prevents rapid toggling', () {
    test('entering dead zone after being ahead does not flip', () {
      sut.evaluate(20.0); // ahead
      expect(sut.evaluate(2.0), isNull); // dead zone
      expect(sut.lastSign, 1); // stays ahead
    });

    test('entering dead zone after being behind does not flip', () {
      sut.evaluate(-20.0); // behind
      expect(sut.evaluate(-2.0), isNull); // dead zone
      expect(sut.lastSign, -1); // stays behind
    });

    test('crossing zero slowly: behind -> dead zone -> ahead', () {
      sut.evaluate(-20.0); // behind
      expect(sut.evaluate(-3.0), isNull); // dead zone
      expect(sut.evaluate(0.0), isNull); // dead zone
      expect(sut.evaluate(3.0), isNull); // still dead zone
      final event = sut.evaluate(6.0); // exits dead zone -> ahead
      expect(event!.payload['action'], 'GHOST_PASSED');
    });
  });

  group('reset', () {
    test('reset clears state, next eval is first observation', () {
      sut.evaluate(-10.0);
      sut.evaluate(10.0); // fires GHOST_PASSED
      sut.reset();
      expect(sut.lastSign, 0);
      // After reset, first eval should not fire
      expect(sut.evaluate(10.0), isNull);
      expect(sut.lastSign, 1);
    });
  });

  group('custom minDeltaM', () {
    test('minDeltaM = 10 expands dead zone', () {
      final wide = GhostVoiceTrigger(minDeltaM: 10.0);
      wide.evaluate(-15.0); // behind
      expect(wide.evaluate(8.0), isNull); // within 10m dead zone
      expect(wide.lastSign, -1); // unchanged
      expect(wide.evaluate(11.0), isNotNull); // now outside dead zone
    });

    test('minDeltaM = 0 has no dead zone', () {
      final tight = GhostVoiceTrigger(minDeltaM: 0.0);
      tight.evaluate(-0.1); // behind
      final event = tight.evaluate(0.1); // ahead (any positive)
      expect(event!.payload['action'], 'GHOST_PASSED');
    });
  });

  group('synthetic race simulation', () {
    test('runner starts behind, overtakes at midpoint, ghost catches up', () {
      final events = <String>[];
      // Phase 1: runner behind ghost (delta negative, shrinking)
      for (final d in [-50.0, -40.0, -30.0, -20.0, -10.0]) {
        final e = sut.evaluate(d);
        if (e != null) events.add(e.payload['action'] as String);
      }
      // Phase 2: runner overtakes (crosses zero)
      for (final d in [-3.0, 0.0, 3.0, 8.0]) {
        final e = sut.evaluate(d);
        if (e != null) events.add(e.payload['action'] as String);
      }
      // Phase 3: runner pulls ahead
      for (final d in [15.0, 25.0, 35.0]) {
        final e = sut.evaluate(d);
        if (e != null) events.add(e.payload['action'] as String);
      }
      // Phase 4: ghost catches up
      for (final d in [20.0, 10.0, 3.0, -3.0, -10.0]) {
        final e = sut.evaluate(d);
        if (e != null) events.add(e.payload['action'] as String);
      }

      expect(events, ['GHOST_PASSED', 'GHOST_PASSED_BY']);
    });
  });
}
