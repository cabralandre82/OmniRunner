import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/usecases/pace_guidance_voice_trigger.dart';

void main() {
  group('PaceGuidanceVoiceTrigger — invariants', () {
    test('confirmCount/cooldownMs/deadbandSec must be non-negative', () {
      expect(() => PaceGuidanceVoiceTrigger(confirmCount: 0),
          throwsA(isA<AssertionError>()));
      expect(() => PaceGuidanceVoiceTrigger(cooldownMs: -1),
          throwsA(isA<AssertionError>()));
      expect(() => PaceGuidanceVoiceTrigger(deadbandSec: -1),
          throwsA(isA<AssertionError>()));
    });

    test('wire strings are the documented snake_case contract', () {
      expect(PaceGuidanceState.onTarget.wire, 'on_target');
      expect(PaceGuidanceState.tooFast.wire, 'too_fast');
      expect(PaceGuidanceState.tooSlow.wire, 'too_slow');
    });

    test('starts in onTarget state', () {
      expect(PaceGuidanceVoiceTrigger().currentState,
          PaceGuidanceState.onTarget);
    });
  });

  group('PaceGuidanceVoiceTrigger — degenerate inputs are silent', () {
    final t = PaceGuidanceVoiceTrigger(
        confirmCount: 1, cooldownMs: 0, deadbandSec: 0);

    AudioEventEntity? fire({
      double? pace,
      int? min,
      int? max,
    }) =>
        t.evaluate(
          currentPaceSecPerKm: pace,
          targetPaceMinSecPerKm: min,
          targetPaceMaxSecPerKm: max,
          timestampMs: 0,
        );

    test('null pace → null', () => expect(fire(min: 300, max: 360), isNull));
    test('NaN pace → null',
        () => expect(fire(pace: double.nan, min: 300, max: 360), isNull));
    test('infinite pace → null',
        () => expect(fire(pace: double.infinity, min: 300, max: 360), isNull));
    test('zero pace → null',
        () => expect(fire(pace: 0, min: 300, max: 360), isNull));
    test('negative pace → null',
        () => expect(fire(pace: -1, min: 300, max: 360), isNull));

    test('null target band → null',
        () => expect(fire(pace: 300, min: null, max: null), isNull));
    test('zero target min → null',
        () => expect(fire(pace: 300, min: 0, max: 360), isNull));
    test('inverted band (min > max) → null',
        () => expect(fire(pace: 300, min: 400, max: 360), isNull));
  });

  group('PaceGuidanceVoiceTrigger — classification', () {
    const min = 300; // 5:00/km
    const max = 360; // 6:00/km

    test('inside band → onTarget, no cue on first tick', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 0, deadbandSec: 0);
      final ev = t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(ev, isNull);
      expect(t.currentState, PaceGuidanceState.onTarget);
    });

    test('pace below min-deadband → tooFast after confirmCount ticks', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 3, cooldownMs: 0, deadbandSec: 5);

      AudioEventEntity? ev;
      for (var i = 0; i < 3; i++) {
        ev = t.evaluate(
          currentPaceSecPerKm: 280, // well below 300 − 5
          targetPaceMinSecPerKm: min,
          targetPaceMaxSecPerKm: max,
          timestampMs: i * 1000,
        );
      }
      expect(ev, isNotNull);
      expect(ev!.type, AudioEventType.paceAlert);
      expect(ev.payload['state'], 'too_fast');
      expect(ev.payload['deviationSec'], 20);
      expect(ev.payload['currentPaceSecPerKm'], 280);
      expect(ev.payload['targetMinSecPerKm'], min);
      expect(ev.payload['targetMaxSecPerKm'], max);
      expect(t.currentState, PaceGuidanceState.tooFast);
    });

    test('pace above max+deadband → tooSlow after confirmCount ticks', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 2, cooldownMs: 0, deadbandSec: 5);

      AudioEventEntity? ev;
      for (var i = 0; i < 2; i++) {
        ev = t.evaluate(
          currentPaceSecPerKm: 400,
          targetPaceMinSecPerKm: min,
          targetPaceMaxSecPerKm: max,
          timestampMs: i * 1000,
        );
      }
      expect(ev, isNotNull);
      expect(ev!.payload['state'], 'too_slow');
      expect(ev.payload['deviationSec'], 40);
    });

    test('deadband suppresses borderline readings', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 0, deadbandSec: 10);
      for (var i = 0; i < 3; i++) {
        final ev = t.evaluate(
          currentPaceSecPerKm: 295, // inside [300−10, 360+10]
          targetPaceMinSecPerKm: min,
          targetPaceMaxSecPerKm: max,
          timestampMs: i * 1000,
        );
        expect(ev, isNull);
      }
      expect(t.currentState, PaceGuidanceState.onTarget);
    });
  });

  group('PaceGuidanceVoiceTrigger — hysteresis', () {
    const min = 300;
    const max = 360;

    test('single off-band reading does not flip state', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 3, cooldownMs: 0, deadbandSec: 0);

      final ev = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(ev, isNull);
      expect(t.currentState, PaceGuidanceState.onTarget);
    });

    test('on-band reading resets pending counter', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 3, cooldownMs: 0, deadbandSec: 0);

      t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 1000,
      );
      // Drifts back into band — pending must reset.
      t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 2000,
      );
      final ev = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 3000,
      );
      expect(ev, isNull);
      expect(t.currentState, PaceGuidanceState.onTarget);
    });
  });

  group('PaceGuidanceVoiceTrigger — cooldown & reinforcement', () {
    const min = 300;
    const max = 360;

    test('second alert inside cooldown window is suppressed', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 30000, deadbandSec: 0);

      final first = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(first, isNotNull);

      // Transition through on_target (always audible), then back to
      // an alert. The alert is the same *kind* of cue (tooFast/
      // tooSlow) as the one we just emitted and the cooldown window
      // has not elapsed ⇒ suppressed.
      t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 5000,
      );
      final second = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 10000,
      );
      expect(second, isNull);
    });

    test('too_slow inside cooldown after too_fast is also suppressed', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 30000, deadbandSec: 0);

      t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 5000,
      );
      final slow = t.evaluate(
        currentPaceSecPerKm: 420,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 10000,
      );
      expect(slow, isNull);
    });

    test('alert after cooldown fires again', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 10000, deadbandSec: 0);

      final first = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(first, isNotNull);

      t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 5000,
      );
      final second = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 20000,
      );
      expect(second, isNotNull);
      expect(second!.payload['state'], 'too_fast');
    });

    test('on_target reinforcement is never suppressed by cooldown', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 600000, deadbandSec: 0);

      t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      final back = t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 1,
      );
      expect(back, isNotNull);
      expect(back!.payload['state'], 'on_target');
    });

    test('transition emits reinforcement on_target cue', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 0, deadbandSec: 0);

      final tooFast = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(tooFast, isNotNull);
      expect(tooFast!.payload['state'], 'too_fast');

      final back = t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 1000,
      );
      expect(back, isNotNull);
      expect(back!.payload['state'], 'on_target');
      expect(back.payload['deviationSec'], 0);
    });

    test('reinforcement cue has lower priority than alerts', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 0, deadbandSec: 0);
      final tooFast = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      )!;
      final back = t.evaluate(
        currentPaceSecPerKm: 330,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 1000,
      )!;
      expect(back.priority, greaterThan(tooFast.priority));
    });
  });

  group('PaceGuidanceVoiceTrigger — reset', () {
    const min = 300;
    const max = 360;

    test('reset clears cooldown and state', () {
      final t = PaceGuidanceVoiceTrigger(
          confirmCount: 1, cooldownMs: 60000, deadbandSec: 0);

      t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 0,
      );
      expect(t.currentState, PaceGuidanceState.tooFast);

      t.reset();
      expect(t.currentState, PaceGuidanceState.onTarget);

      final ev = t.evaluate(
        currentPaceSecPerKm: 250,
        targetPaceMinSecPerKm: min,
        targetPaceMaxSecPerKm: max,
        timestampMs: 1000,
      );
      expect(ev, isNotNull);
      expect(ev!.payload['state'], 'too_fast');
    });
  });
}
