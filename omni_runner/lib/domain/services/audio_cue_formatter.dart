import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

/// Pure, locale-aware formatter for [AudioEventEntity] -> spoken text.
///
/// Responsibility: take a structured event + payload and emit the
/// exact string the TTS engine should speak, in the locale the coach
/// was configured for. Keeps all translation tables in a single
/// place so we can enforce coverage in CI (one entry per event type
/// per locale, no gaps).
///
/// Finding reference: L22-06 (Voice coaching parcial).
class AudioCueFormatter {
  final AudioCoachLocale locale;

  const AudioCueFormatter({this.locale = AudioCoachLocale.ptBR});

  /// Build the spoken string for [event] in [locale].
  ///
  /// Contract:
  /// - If `event.payload['text']` exists, it is returned verbatim
  ///   (pre-composed text path — caller has already localised).
  /// - Otherwise, dispatched per [AudioEventType] through the locale
  ///   catalogue. Missing payload keys collapse to neutral phrases
  ///   rather than emit empty strings, so the coach never goes silent
  ///   on a malformed event.
  String format(AudioEventEntity event) {
    final payload = event.payload;
    final preComposed = payload['text'];
    if (preComposed is String && preComposed.isNotEmpty) return preComposed;

    return switch (event.type) {
      AudioEventType.distanceAnnouncement => _distance(payload),
      AudioEventType.timeAnnouncement => _time(payload),
      AudioEventType.paceAlert => _pace(payload),
      AudioEventType.heartRateAlert => _hr(payload),
      AudioEventType.sessionEvent => _session(payload),
      AudioEventType.countdown => _countdown(payload),
      AudioEventType.custom => '',
    };
  }

  String _distance(Map<String, Object> p) {
    final km = p['distanceKm'];
    final pace = p['paceFormatted'];
    if (km == null) return '';
    final kmText = _phrase(_distanceKmKey, {'km': '$km'});
    if (pace == null) return kmText;
    return '$kmText. ${_phrase(_paceUnitKey, {'pace': '$pace'})}';
  }

  String _time(Map<String, Object> p) {
    final min = p['elapsedMin'];
    if (min == null) return '';
    return _phrase(_timeMinutesKey, {'minutes': '$min'});
  }

  String _pace(Map<String, Object> p) {
    final msg = p['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    return _phrase(_paceDefaultKey, const {});
  }

  String _hr(Map<String, Object> p) {
    final zone = p['zone'];
    final bpm = p['bpm'];
    final direction = p['direction'];
    if (zone == null) return _phrase(_hrFallbackKey, const {});
    final buf = StringBuffer(_phrase(_hrZoneKey, {'zone': '$zone'}));
    if (direction == 'up') {
      buf.write('. ${_phrase(_hrUpKey, const {})}');
    } else if (direction == 'down') {
      buf.write('. ${_phrase(_hrDownKey, const {})}');
    }
    if (bpm != null) buf.write('. ${_phrase(_hrBpmKey, {'bpm': '$bpm'})}');
    return buf.toString();
  }

  String _session(Map<String, Object> p) {
    final action = p['action']?.toString();
    return switch (action) {
      'start' => _phrase(_sessionStartKey, const {}),
      'pause' => _phrase(_sessionPauseKey, const {}),
      'resume' => _phrase(_sessionResumeKey, const {}),
      'finish' => _phrase(_sessionFinishKey, const {}),
      _ => '',
    };
  }

  String _countdown(Map<String, Object> p) {
    final n = p['value'];
    if (n == null) return '';
    if (n == 0) return _phrase(_countdownGoKey, const {});
    return '$n';
  }

  /// Ordered list of motivational phrases for this locale.
  ///
  /// Callers are expected to rotate through this list (modulo its
  /// length) so repeated prompts feel varied rather than robotic.
  List<String> motivationalPhrases() => _motivationalPhrases[locale]!;

  /// Single hydration reminder phrase for this locale.
  String hydrationReminder() => _phrase(_hydrationKey, const {});

  // ---- catalogue plumbing ----

  String _phrase(String key, Map<String, String> vars) {
    final table = _catalogue[locale]!;
    var template = table[key] ?? _catalogue[AudioCoachLocale.ptBR]![key] ?? '';
    vars.forEach((name, value) {
      template = template.replaceAll('{$name}', value);
    });
    return template;
  }

  static const _distanceKmKey = 'distance.km';
  static const _paceUnitKey = 'pace.unit';
  static const _timeMinutesKey = 'time.minutes';
  static const _paceDefaultKey = 'pace.default';
  static const _hrZoneKey = 'hr.zone';
  static const _hrUpKey = 'hr.up';
  static const _hrDownKey = 'hr.down';
  static const _hrBpmKey = 'hr.bpm';
  static const _hrFallbackKey = 'hr.fallback';
  static const _sessionStartKey = 'session.start';
  static const _sessionPauseKey = 'session.pause';
  static const _sessionResumeKey = 'session.resume';
  static const _sessionFinishKey = 'session.finish';
  static const _countdownGoKey = 'countdown.go';
  static const _hydrationKey = 'hydration.reminder';

  /// Canonical set of translation keys. Kept public for the
  /// `check-audio-cues-i18n.ts` CI audit which asserts every locale
  /// covers every key (no gaps, no orphans).
  static const Set<String> translationKeys = {
    _distanceKmKey,
    _paceUnitKey,
    _timeMinutesKey,
    _paceDefaultKey,
    _hrZoneKey,
    _hrUpKey,
    _hrDownKey,
    _hrBpmKey,
    _hrFallbackKey,
    _sessionStartKey,
    _sessionPauseKey,
    _sessionResumeKey,
    _sessionFinishKey,
    _countdownGoKey,
    _hydrationKey,
  };

  static const Map<AudioCoachLocale, Map<String, String>> _catalogue = {
    AudioCoachLocale.ptBR: {
      _distanceKmKey: '{km} quilômetros',
      _paceUnitKey: 'Pace {pace} por quilômetro',
      _timeMinutesKey: '{minutes} minutos',
      _paceDefaultKey: 'Atenção ao pace',
      _hrZoneKey: 'Zona {zone}',
      _hrUpKey: 'Subindo',
      _hrDownKey: 'Descendo',
      _hrBpmKey: '{bpm} BPM',
      _hrFallbackKey: 'Alerta cardíaco',
      _sessionStartKey: 'Corrida iniciada',
      _sessionPauseKey: 'Pausado',
      _sessionResumeKey: 'Retomando',
      _sessionFinishKey: 'Corrida finalizada',
      _countdownGoKey: 'Vai!',
      _hydrationKey: 'Lembrete: hidrate-se',
    },
    AudioCoachLocale.en: {
      _distanceKmKey: '{km} kilometers',
      _paceUnitKey: 'Pace {pace} per kilometer',
      _timeMinutesKey: '{minutes} minutes',
      _paceDefaultKey: 'Watch your pace',
      _hrZoneKey: 'Zone {zone}',
      _hrUpKey: 'rising',
      _hrDownKey: 'falling',
      _hrBpmKey: '{bpm} BPM',
      _hrFallbackKey: 'Heart rate alert',
      _sessionStartKey: 'Run started',
      _sessionPauseKey: 'Paused',
      _sessionResumeKey: 'Resuming',
      _sessionFinishKey: 'Run finished',
      _countdownGoKey: 'Go!',
      _hydrationKey: 'Reminder: stay hydrated',
    },
    AudioCoachLocale.es: {
      _distanceKmKey: '{km} kilómetros',
      _paceUnitKey: 'Ritmo {pace} por kilómetro',
      _timeMinutesKey: '{minutes} minutos',
      _paceDefaultKey: 'Atención al ritmo',
      _hrZoneKey: 'Zona {zone}',
      _hrUpKey: 'subiendo',
      _hrDownKey: 'bajando',
      _hrBpmKey: '{bpm} pulsaciones',
      _hrFallbackKey: 'Alerta cardíaca',
      _sessionStartKey: 'Carrera iniciada',
      _sessionPauseKey: 'Pausado',
      _sessionResumeKey: 'Reanudando',
      _sessionFinishKey: 'Carrera finalizada',
      _countdownGoKey: '¡Vamos!',
      _hydrationKey: 'Recordatorio: hidrátate',
    },
  };

  static const Map<AudioCoachLocale, List<String>> _motivationalPhrases = {
    AudioCoachLocale.ptBR: [
      'Você está indo muito bem!',
      'Continue firme, respire fundo.',
      'Cada passo conta. Segue forte!',
      'Confia no processo, você consegue.',
      'Mantém o ritmo, cabeça erguida!',
    ],
    AudioCoachLocale.en: [
      "You're doing great!",
      'Keep going, breathe deep.',
      'Every step counts. Stay strong!',
      'Trust the process, you got this.',
      'Hold your pace, head up!',
    ],
    AudioCoachLocale.es: [
      '¡Lo estás haciendo genial!',
      'Sigue firme, respira hondo.',
      'Cada paso cuenta. ¡Tú puedes!',
      'Confía en el proceso.',
      'Mantén el ritmo, ¡arriba!',
    ],
  };
}
