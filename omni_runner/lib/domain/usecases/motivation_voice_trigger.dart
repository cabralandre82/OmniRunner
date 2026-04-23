import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';

/// Emits periodic motivational phrases every [intervalMs] of
/// **moving** time (pauses don't count — a stopped runner already
/// has enough stimulation).
///
/// Rotates through the formatter's motivational pool so identical
/// phrases aren't repeated back-to-back. Rotation is modulo the
/// pool length — if the pool has 5 phrases, the 6th prompt wraps
/// to the first.
///
/// Cool-down: subsequent prompts within [minSpacingMs] of the
/// previous one are suppressed, even across resume/pause cycles.
/// This guards against the corner case where the interval fires
/// right after another high-priority cue finished.
///
/// Stateful — call [reset] when starting a new session.
///
/// Finding reference: L22-06 (Voice coaching parcial).
final class MotivationVoiceTrigger {
  /// Moving-time interval between motivational phrases (ms).
  final int intervalMs;

  /// Minimum milliseconds between any two motivational prompts.
  final int minSpacingMs;

  /// Formatter providing the locale-specific phrase pool.
  final AudioCueFormatter formatter;

  int _lastAnnouncedInterval = 0;
  int _lastFiredMovingMs = -1 << 30;
  int _rotationIndex = 0;

  MotivationVoiceTrigger({
    required this.formatter,
    this.intervalMs = 10 * 60 * 1000,
    this.minSpacingMs = 2 * 60 * 1000,
  })  : assert(intervalMs > 0, 'intervalMs must be positive'),
        assert(minSpacingMs >= 0, 'minSpacingMs must be non-negative');

  /// Exposed for tests.
  int get lastAnnouncedInterval => _lastAnnouncedInterval;

  /// Next phrase the trigger will emit (without advancing).
  String peekNextPhrase() {
    final pool = formatter.motivationalPhrases();
    return pool[_rotationIndex % pool.length];
  }

  /// Reset for a new session.
  void reset() {
    _lastAnnouncedInterval = 0;
    _lastFiredMovingMs = -1 << 30;
    _rotationIndex = 0;
  }

  /// Evaluate [metrics] for the current tick.
  ///
  /// Returns a motivational [AudioEventEntity] if enough moving time
  /// has elapsed since the last prompt, or `null` otherwise.
  AudioEventEntity? evaluate(
    WorkoutMetricsEntity metrics, {
    bool isPaused = false,
  }) {
    if (isPaused) return null;
    final movingMs = metrics.movingMs;
    if (movingMs <= 0) return null;

    final currentInterval = movingMs ~/ intervalMs;
    if (currentInterval <= 0 || currentInterval <= _lastAnnouncedInterval) {
      return null;
    }
    if ((movingMs - _lastFiredMovingMs) < minSpacingMs) {
      return null;
    }

    _lastAnnouncedInterval = currentInterval;
    _lastFiredMovingMs = movingMs;

    final pool = formatter.motivationalPhrases();
    final phrase = pool[_rotationIndex % pool.length];
    _rotationIndex++;

    return AudioEventEntity(
      type: AudioEventType.custom,
      priority: 14,
      payload: {
        'text': phrase,
        'action': 'MOTIVATION',
      },
    );
  }
}
