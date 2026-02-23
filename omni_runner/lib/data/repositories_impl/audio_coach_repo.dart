import 'dart:collection';

import 'package:omni_runner/data/datasources/audio_coach_service.dart';
import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/repositories/i_audio_coach.dart';

/// Concrete [IAudioCoach] with a priority-based queue.
///
/// Rules:
/// - priority <= [interruptThreshold] (default 5): stop current, speak now.
/// - priority <= [queueThreshold] (default 15): enqueue (max [maxQueueSize]).
/// - priority > [queueThreshold]: discard if queue is non-empty.
///
/// Queue is drained FIFO; on completion the next item is spoken automatically.
class AudioCoachRepo implements IAudioCoach {
  final AudioCoachService _service;
  final int interruptThreshold;
  final int queueThreshold;
  final int maxQueueSize;

  final Queue<AudioEventEntity> _queue = Queue<AudioEventEntity>();
  bool _draining = false;

  AudioCoachRepo({
    required AudioCoachService service,
    this.interruptThreshold = 5,
    this.queueThreshold = 15,
    this.maxQueueSize = 5,
  }) : _service = service;

  @override
  Future<void> init() => _service.init();

  @override
  Future<void> speak(AudioEventEntity event) async {
    if (!_service.isSpeaking) {
      await _speak(event);
      return;
    }
    // High priority → interrupt current speech.
    if (event.priority <= interruptThreshold) {
      await _service.stop();
      _queue.clear();
      await _speak(event);
      return;
    }
    // Normal priority → enqueue if room.
    if (event.priority <= queueThreshold) {
      if (_queue.length < maxQueueSize) _queue.addLast(event);
      return;
    }
    // Low priority → discard when queue non-empty.
    if (_queue.isEmpty) {
      _queue.addLast(event);
    }
  }

  @override
  Future<void> dispose() async {
    _queue.clear();
    await _service.dispose();
  }

  // -- internals --

  Future<void> _speak(AudioEventEntity event) async {
    final text = _buildText(event);
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
      final text = _buildText(next);
      if (text.isNotEmpty) await _service.speak(text);
    }
    _draining = false;
  }

  /// Convert [AudioEventEntity] to spoken text.
  ///
  /// If payload contains a `text` key, use it directly.
  /// Otherwise builds a minimal phrase from the event type and payload.
  static String _buildText(AudioEventEntity event) {
    final p = event.payload;
    if (p.containsKey('text')) return p['text'].toString();
    return switch (event.type) {
      AudioEventType.distanceAnnouncement => _distanceText(p),
      AudioEventType.timeAnnouncement => _timeText(p),
      AudioEventType.paceAlert => _paceText(p),
      AudioEventType.heartRateAlert => _hrText(p),
      AudioEventType.sessionEvent => _sessionText(p),
      AudioEventType.countdown => _countdownText(p),
      AudioEventType.custom => '',
    };
  }

  static String _distanceText(Map<String, Object> p) {
    final km = p['distanceKm'];
    final pace = p['paceFormatted'];
    if (km == null) return '';
    final buf = StringBuffer('$km quilômetros');
    if (pace != null) buf.write('. Pace $pace por quilômetro');
    return buf.toString();
  }

  static String _timeText(Map<String, Object> p) {
    final min = p['elapsedMin'];
    return min != null ? '$min minutos' : '';
  }

  static String _paceText(Map<String, Object> p) {
    final msg = p['message'];
    return msg?.toString() ?? 'Atenção ao pace';
  }

  static String _hrText(Map<String, Object> p) {
    final zone = p['zone'];
    final bpm = p['bpm'];
    final direction = p['direction'];
    if (zone == null) return 'Alerta cardíaco';
    final buf = StringBuffer('Zona $zone');
    if (direction == 'up') {
      buf.write('. Subindo');
    } else if (direction == 'down') {
      buf.write('. Descendo');
    }
    if (bpm != null) buf.write('. $bpm BPM');
    return buf.toString();
  }

  static String _sessionText(Map<String, Object> p) {
    final action = p['action'];
    return switch (action?.toString()) {
      'start' => 'Corrida iniciada',
      'pause' => 'Pausado',
      'resume' => 'Retomando',
      'finish' => 'Corrida finalizada',
      _ => '',
    };
  }

  static String _countdownText(Map<String, Object> p) {
    final n = p['value'];
    return n != null ? '$n' : '';
  }
}
