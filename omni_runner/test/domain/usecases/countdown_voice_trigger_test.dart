import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/usecases/countdown_voice_trigger.dart';

void main() {
  group('CountdownVoiceTrigger (default 5s)', () {
    late CountdownVoiceTrigger sut;

    setUp(() => sut = CountdownVoiceTrigger());

    test('fires 5 at t=0', () {
      final event = sut.evaluate(0);
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.countdown);
      expect(event.payload['value'], 5);
      expect(event.priority, 2);
    });

    test('does not fire twice within the same second', () {
      expect(sut.evaluate(0), isNotNull);
      expect(sut.evaluate(500), isNull);
      expect(sut.evaluate(999), isNull);
    });

    test('fires 4 at t=1000', () {
      sut.evaluate(0);
      final event = sut.evaluate(1000);
      expect(event!.payload['value'], 4);
    });

    test('fires full 5..0 sequence', () {
      final values = <int>[];
      for (var tMs = 0; tMs <= 5000; tMs += 1000) {
        final event = sut.evaluate(tMs);
        if (event != null) values.add(event.payload['value'] as int);
      }
      expect(values, [5, 4, 3, 2, 1, 0]);
    });

    test('does not fire past the countdown', () {
      for (var tMs = 0; tMs <= 5000; tMs += 1000) {
        sut.evaluate(tMs);
      }
      expect(sut.evaluate(6000), isNull);
      expect(sut.evaluate(10000), isNull);
    });

    test('negative elapsedMs is ignored', () {
      expect(sut.evaluate(-1), isNull);
    });

    test('skipped second fires the latest boundary', () {
      sut.evaluate(0);
      final event = sut.evaluate(3200);
      expect(event!.payload['value'], 2);
      expect(sut.lastAnnouncedRemaining, 2);
    });

    test('reset re-arms the countdown', () {
      for (var tMs = 0; tMs <= 5000; tMs += 1000) {
        sut.evaluate(tMs);
      }
      expect(sut.evaluate(0), isNull);
      sut.reset();
      expect(sut.lastAnnouncedRemaining, 6);
      final event = sut.evaluate(0);
      expect(event!.payload['value'], 5);
    });
  });

  group('CountdownVoiceTrigger (custom length 3)', () {
    test('fires 3,2,1,GO', () {
      final sut = CountdownVoiceTrigger(countdownSec: 3);
      final values = <int>[];
      for (var tMs = 0; tMs <= 3000; tMs += 1000) {
        final event = sut.evaluate(tMs);
        if (event != null) values.add(event.payload['value'] as int);
      }
      expect(values, [3, 2, 1, 0]);
    });

    test('countdownSec <= 0 rejected', () {
      expect(() => CountdownVoiceTrigger(countdownSec: 0), throwsA(isA<AssertionError>()));
      expect(() => CountdownVoiceTrigger(countdownSec: -1), throwsA(isA<AssertionError>()));
    });
  });
}
