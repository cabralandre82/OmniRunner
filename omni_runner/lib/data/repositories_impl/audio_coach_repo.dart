import 'dart:collection';

import 'package:omni_runner/data/datasources/audio_coach_service.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/repositories/i_audio_coach.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';
import 'package:omni_runner/domain/value_objects/audio_coach_locale.dart';

/// Concrete [IAudioCoach] with a priority-based queue.
///
/// Rules:
/// - priority <= [interruptThreshold] (default 5): stop current, speak now.
/// - priority <= [queueThreshold] (default 15): enqueue (max [maxQueueSize]).
/// - priority > [queueThreshold]: discard if queue is non-empty.
///
/// Queue is drained FIFO; on completion the next item is spoken automatically.
///
/// L22-06: text rendering is delegated to [AudioCueFormatter] so the
/// repo stays locale-agnostic. Callers can swap locale via [setLocale].
class AudioCoachRepo implements IAudioCoach {
  final AudioCoachService _service;
  final int interruptThreshold;
  final int queueThreshold;
  final int maxQueueSize;
  AudioCueFormatter _formatter;

  final Queue<AudioEventEntity> _queue = Queue<AudioEventEntity>();
  bool _draining = false;

  AudioCoachRepo({
    required AudioCoachService service,
    AudioCueFormatter? formatter,
    this.interruptThreshold = 5,
    this.queueThreshold = 15,
    this.maxQueueSize = 5,
  })  : _service = service,
        _formatter = formatter ?? const AudioCueFormatter();

  /// The current formatter (exposed for tests and diagnostics).
  AudioCueFormatter get formatter => _formatter;

  /// Current coach locale.
  AudioCoachLocale get locale => _formatter.locale;

  @override
  Future<void> init() => _service.init(locale: _formatter.locale);

  /// Swap the active locale. Updates both the formatter used to
  /// render future events and the TTS engine itself.
  Future<void> setLocale(AudioCoachLocale locale) async {
    _formatter = AudioCueFormatter(locale: locale);
    await _service.setLocale(locale);
  }

  @override
  Future<void> speak(AudioEventEntity event) async {
    if (!_service.isSpeaking) {
      await _speak(event);
      return;
    }
    if (event.priority <= interruptThreshold) {
      await _service.stop();
      _queue.clear();
      await _speak(event);
      return;
    }
    if (event.priority <= queueThreshold) {
      if (_queue.length < maxQueueSize) _queue.addLast(event);
      return;
    }
    if (_queue.isEmpty) {
      _queue.addLast(event);
    }
  }

  @override
  Future<void> dispose() async {
    _queue.clear();
    await _service.dispose();
  }

  Future<void> _speak(AudioEventEntity event) async {
    final text = _formatter.format(event);
    if (text.isEmpty) return;
    await _service.speak(text);
    _drainQueue();
  }

  /// Drain the queue sequentially after each utterance completes.
  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      final text = _formatter.format(next);
      if (text.isNotEmpty) await _service.speak(text);
    }
    _draining = false;
  }
}
