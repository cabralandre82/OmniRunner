import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';
import 'package:omni_runner/domain/usecases/hydration_voice_trigger.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

WorkoutMetricsEntity _m(int movingMs) => WorkoutMetricsEntity(
      totalDistanceM: 0,
      elapsedMs: movingMs,
      movingMs: movingMs,
      pointsCount: 0,
    );

void main() {
  group('HydrationVoiceTrigger (default 20min/20min)', () {
    late HydrationVoiceTrigger sut;

    setUp(() => sut = HydrationVoiceTrigger(formatter: const AudioCueFormatter()));

    test('silent during warmup window', () {
      expect(sut.evaluate(_m(0)), isNull);
      expect(sut.evaluate(_m(10 * 60 * 1000)), isNull);
      expect(sut.evaluate(_m(19 * 60 * 1000)), isNull);
    });

    test('fires at first boundary (20 min)', () {
      final event = sut.evaluate(_m(20 * 60 * 1000));
      expect(event, isNotNull);
      expect(event!.type, AudioEventType.custom);
      expect(event.payload['action'], 'HYDRATION');
      expect(event.payload['text'], 'Lembrete: hidrate-se');
      expect(event.priority, 13);
    });

    test('does not double-fire within the same interval', () {
      expect(sut.evaluate(_m(20 * 60 * 1000)), isNotNull);
      expect(sut.evaluate(_m(25 * 60 * 1000)), isNull);
      expect(sut.evaluate(_m(39 * 60 * 1000)), isNull);
    });

    test('fires again at 40 min', () {
      sut.evaluate(_m(20 * 60 * 1000));
      final event = sut.evaluate(_m(40 * 60 * 1000));
      expect(event, isNotNull);
    });

    test('isPaused suppresses emission', () {
      expect(sut.evaluate(_m(25 * 60 * 1000), isPaused: true), isNull);
    });

    test('reset re-arms the trigger', () {
      sut.evaluate(_m(20 * 60 * 1000));
      sut.reset();
      expect(sut.lastFiredMovingMs, -1);
      final event = sut.evaluate(_m(20 * 60 * 1000));
      expect(event, isNotNull);
    });
  });

  group('HydrationVoiceTrigger (custom config)', () {
    test('shorter warmup allows earlier prompt', () {
      final sut = HydrationVoiceTrigger(
        formatter: const AudioCueFormatter(),
        warmupMs: 5 * 60 * 1000,
        intervalMs: 5 * 60 * 1000,
      );
      expect(sut.evaluate(_m(4 * 60 * 1000)), isNull);
      final event = sut.evaluate(_m(5 * 60 * 1000));
      expect(event, isNotNull);
    });

    test('en locale uses English hydration phrase', () {
      final sut = HydrationVoiceTrigger(
        formatter: const AudioCueFormatter(locale: AudioCoachLocale.en),
      );
      final event = sut.evaluate(_m(20 * 60 * 1000));
      expect(event!.payload['text'], 'Reminder: stay hydrated');
    });

    test('es locale uses Spanish hydration phrase', () {
      final sut = HydrationVoiceTrigger(
        formatter: const AudioCueFormatter(locale: AudioCoachLocale.es),
      );
      final event = sut.evaluate(_m(20 * 60 * 1000));
      expect(event!.payload['text'], 'Recordatorio: hidrátate');
    });
  });
}
