import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';
import 'package:omni_runner/domain/usecases/motivation_voice_trigger.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

WorkoutMetricsEntity _m(int movingMs) => WorkoutMetricsEntity(
      totalDistanceM: 0,
      elapsedMs: movingMs,
      movingMs: movingMs,
      pointsCount: 0,
    );

void main() {
  group('MotivationVoiceTrigger (default 10min/2min cool-down)', () {
    late MotivationVoiceTrigger sut;

    setUp(
      () => sut = MotivationVoiceTrigger(
        formatter: const AudioCueFormatter(),
      ),
    );

    test('no fire before interval', () {
      expect(sut.evaluate(_m(0)), isNull);
      expect(sut.evaluate(_m(5 * 60 * 1000)), isNull);
      expect(sut.evaluate(_m(9 * 60 * 1000 + 59999)), isNull);
    });

    test('fires at first 10-min boundary with motivational text', () {
      final event = sut.evaluate(_m(10 * 60 * 1000));
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.custom);
      expect(event.payload['action'], 'MOTIVATION');
      expect(event.payload['text'], isA<String>());
      expect((event.payload['text'] as String).isNotEmpty, isTrue);
      expect(event.priority, 14);
    });

    test('does not double-fire within same interval window', () {
      expect(sut.evaluate(_m(10 * 60 * 1000)), isNotNull);
      expect(sut.evaluate(_m(11 * 60 * 1000)), isNull);
      expect(sut.evaluate(_m(19 * 60 * 1000)), isNull);
    });

    test('fires again at 20 min and rotates phrase', () {
      final first = sut.evaluate(_m(10 * 60 * 1000));
      final second = sut.evaluate(_m(20 * 60 * 1000));
      expect(second, isNotNull);
      expect(second!.payload['text'], isNot(equals(first!.payload['text'])));
    });

    test('isPaused suppresses emission', () {
      final event = sut.evaluate(_m(10 * 60 * 1000), isPaused: true);
      expect(event, isNull);
    });

    test('rotation wraps through the pool', () {
      final seen = <String>[];
      for (var intervalIdx = 1; intervalIdx <= 6; intervalIdx++) {
        final event = sut.evaluate(_m(intervalIdx * 10 * 60 * 1000));
        if (event != null) seen.add(event.payload['text'] as String);
      }
      final pool = const AudioCueFormatter().motivationalPhrases();
      expect(seen.length, pool.length + 1);
      expect(seen.last, pool.first);
    });

    test('reset restores initial state', () {
      sut.evaluate(_m(10 * 60 * 1000));
      sut.reset();
      expect(sut.lastAnnouncedInterval, 0);
      expect(sut.peekNextPhrase(), const AudioCueFormatter().motivationalPhrases().first);
    });
  });

  group('MotivationVoiceTrigger (custom intervals + locale)', () {
    test('custom 5-min interval fires earlier', () {
      final sut = MotivationVoiceTrigger(
        formatter: const AudioCueFormatter(),
        intervalMs: 5 * 60 * 1000,
        minSpacingMs: 0,
      );
      expect(sut.evaluate(_m(4 * 60 * 1000)), isNull);
      final event = sut.evaluate(_m(5 * 60 * 1000));
      expect(event, isNotNull);
    });

    test('en locale uses English motivational pool', () {
      final sut = MotivationVoiceTrigger(
        formatter: const AudioCueFormatter(locale: AudioCoachLocale.en),
      );
      final event = sut.evaluate(_m(10 * 60 * 1000));
      expect(event, isNotNull);
      expect(event!.payload['text'], isIn(
        const AudioCueFormatter(locale: AudioCoachLocale.en).motivationalPhrases(),
      ));
    });
  });
}
