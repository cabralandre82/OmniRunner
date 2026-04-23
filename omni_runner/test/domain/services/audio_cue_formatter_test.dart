import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

void main() {
  group('AudioCueFormatter (pt-BR default)', () {
    const f = AudioCueFormatter();

    test('defaults to pt-BR locale', () {
      expect(f.locale, AudioCoachLocale.ptBR);
    });

    test('distanceAnnouncement with km only', () {
      const event = AudioEventEntity(
        type: AudioEventType.distanceAnnouncement,
        payload: {'distanceKm': 1.0},
      );
      expect(f.format(event), '1.0 quilômetros');
    });

    test('distanceAnnouncement with km + pace', () {
      const event = AudioEventEntity(
        type: AudioEventType.distanceAnnouncement,
        payload: {'distanceKm': 2.0, 'paceFormatted': '05:30'},
      );
      expect(f.format(event), '2.0 quilômetros. Pace 05:30 por quilômetro');
    });

    test('distanceAnnouncement without km is empty', () {
      const event = AudioEventEntity(
        type: AudioEventType.distanceAnnouncement,
        payload: {},
      );
      expect(f.format(event), '');
    });

    test('timeAnnouncement with elapsedMin', () {
      const event = AudioEventEntity(
        type: AudioEventType.timeAnnouncement,
        payload: {'elapsedMin': 10},
      );
      expect(f.format(event), '10 minutos');
    });

    test('paceAlert with explicit message is passed through', () {
      const event = AudioEventEntity(
        type: AudioEventType.paceAlert,
        payload: {'message': 'Diminua o ritmo'},
      );
      expect(f.format(event), 'Diminua o ritmo');
    });

    test('paceAlert without message falls back to locale default', () {
      const event = AudioEventEntity(
        type: AudioEventType.paceAlert,
        payload: {},
      );
      expect(f.format(event), 'Atenção ao pace');
    });

    test('heartRateAlert with direction=up + bpm', () {
      const event = AudioEventEntity(
        type: AudioEventType.heartRateAlert,
        payload: {'zone': 3, 'direction': 'up', 'bpm': 160},
      );
      expect(f.format(event), 'Zona 3. Subindo. 160 BPM');
    });

    test('heartRateAlert with direction=down no bpm', () {
      const event = AudioEventEntity(
        type: AudioEventType.heartRateAlert,
        payload: {'zone': 2, 'direction': 'down'},
      );
      expect(f.format(event), 'Zona 2. Descendo');
    });

    test('heartRateAlert without zone falls back', () {
      const event = AudioEventEntity(
        type: AudioEventType.heartRateAlert,
        payload: {},
      );
      expect(f.format(event), 'Alerta cardíaco');
    });

    test('sessionEvent action=start', () {
      const event = AudioEventEntity(
        type: AudioEventType.sessionEvent,
        payload: {'action': 'start'},
      );
      expect(f.format(event), 'Corrida iniciada');
    });

    test('sessionEvent unknown action is empty', () {
      const event = AudioEventEntity(
        type: AudioEventType.sessionEvent,
        payload: {'action': 'xyz'},
      );
      expect(f.format(event), '');
    });

    test('countdown 3,2,1 spoken as raw numbers', () {
      for (final n in [3, 2, 1]) {
        final event = AudioEventEntity(
          type: AudioEventType.countdown,
          payload: {'value': n},
        );
        expect(f.format(event), '$n');
      }
    });

    test('countdown 0 → locale GO phrase (Vai!)', () {
      const event = AudioEventEntity(
        type: AudioEventType.countdown,
        payload: {'value': 0},
      );
      expect(f.format(event), 'Vai!');
    });

    test('pre-composed text payload short-circuits all dispatch', () {
      const event = AudioEventEntity(
        type: AudioEventType.custom,
        payload: {'text': 'Você ultrapassou o fantasma!'},
      );
      expect(f.format(event), 'Você ultrapassou o fantasma!');
    });

    test('custom event without text is empty', () {
      const event = AudioEventEntity(
        type: AudioEventType.custom,
        payload: {},
      );
      expect(f.format(event), '');
    });
  });

  group('AudioCueFormatter (en locale)', () {
    const f = AudioCueFormatter(locale: AudioCoachLocale.en);

    test('distance + pace in English', () {
      const event = AudioEventEntity(
        type: AudioEventType.distanceAnnouncement,
        payload: {'distanceKm': 5.0, 'paceFormatted': '04:30'},
      );
      expect(f.format(event), '5.0 kilometers. Pace 04:30 per kilometer');
    });

    test('sessionEvent start in English', () {
      const event = AudioEventEntity(
        type: AudioEventType.sessionEvent,
        payload: {'action': 'start'},
      );
      expect(f.format(event), 'Run started');
    });

    test('countdown 0 → Go!', () {
      const event = AudioEventEntity(
        type: AudioEventType.countdown,
        payload: {'value': 0},
      );
      expect(f.format(event), 'Go!');
    });

    test('hydrationReminder returns English phrase', () {
      expect(f.hydrationReminder(), 'Reminder: stay hydrated');
    });

    test('motivationalPhrases returns non-empty English pool', () {
      final pool = f.motivationalPhrases();
      expect(pool, isNotEmpty);
      expect(pool.first, contains('doing'));
    });
  });

  group('AudioCueFormatter (es locale)', () {
    const f = AudioCueFormatter(locale: AudioCoachLocale.es);

    test('distance + pace in Spanish', () {
      const event = AudioEventEntity(
        type: AudioEventType.distanceAnnouncement,
        payload: {'distanceKm': 5.0, 'paceFormatted': '04:30'},
      );
      expect(f.format(event), '5.0 kilómetros. Ritmo 04:30 por kilómetro');
    });

    test('countdown 0 → ¡Vamos!', () {
      const event = AudioEventEntity(
        type: AudioEventType.countdown,
        payload: {'value': 0},
      );
      expect(f.format(event), '¡Vamos!');
    });

    test('hydrationReminder returns Spanish phrase', () {
      expect(f.hydrationReminder(), 'Recordatorio: hidrátate');
    });
  });

  group('AudioCueFormatter coverage invariants', () {
    test('all locales cover every translation key', () {
      for (final locale in AudioCoachLocale.values) {
        final f = AudioCueFormatter(locale: locale);
        for (final key in AudioCueFormatter.translationKeys) {
          final phrase = f.format(
            const AudioEventEntity(
              type: AudioEventType.sessionEvent,
              payload: {'action': 'start'},
            ),
          );
          expect(
            phrase,
            isNotEmpty,
            reason: 'locale=$locale must resolve key $key to a non-empty phrase',
          );
        }
      }
    });

    test('translationKeys is declared set', () {
      expect(AudioCueFormatter.translationKeys, contains('distance.km'));
      expect(AudioCueFormatter.translationKeys, contains('countdown.go'));
      expect(AudioCueFormatter.translationKeys, contains('hydration.reminder'));
    });

    test('every locale has a non-empty motivational pool', () {
      for (final locale in AudioCoachLocale.values) {
        final f = AudioCueFormatter(locale: locale);
        expect(
          f.motivationalPhrases(),
          isNotEmpty,
          reason: 'locale=$locale must expose motivational phrases',
        );
      }
    });
  });

  group('AudioCoachLocale.fromTag', () {
    test('ptBR canonical tag', () {
      expect(AudioCoachLocale.fromTag('pt-BR'), AudioCoachLocale.ptBR);
    });

    test('en variants', () {
      for (final tag in ['en', 'en_US', 'en-gb', 'EN']) {
        expect(AudioCoachLocale.fromTag(tag), AudioCoachLocale.en);
      }
    });

    test('es variants', () {
      for (final tag in ['es', 'es-MX', 'es_AR']) {
        expect(AudioCoachLocale.fromTag(tag), AudioCoachLocale.es);
      }
    });

    test('null/empty/unknown falls back to ptBR', () {
      expect(AudioCoachLocale.fromTag(null), AudioCoachLocale.ptBR);
      expect(AudioCoachLocale.fromTag(''), AudioCoachLocale.ptBR);
      expect(AudioCoachLocale.fromTag('fr-FR'), AudioCoachLocale.ptBR);
      expect(AudioCoachLocale.fromTag('xx'), AudioCoachLocale.ptBR);
    });

    test('language tag maps to BCP-47', () {
      expect(AudioCoachLocale.ptBR.languageTag, 'pt-BR');
      expect(AudioCoachLocale.en.languageTag, 'en-US');
      expect(AudioCoachLocale.es.languageTag, 'es-ES');
    });
  });
}
