import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/services/audio_cue_formatter.dart';

/// Periodic hydration reminders for long runs.
///
/// Silent for the first [warmupMs] of moving time (short runs don't
/// need hydration prompts — the reminder just becomes noise). After
/// warmup, emits a reminder every [intervalMs] of moving time.
///
/// The typical configuration reminds the runner every 20 minutes of
/// actual moving time, starting from minute 20. Pauses don't count:
/// if the runner stops to walk, the clock pauses too.
///
/// Stateful — call [reset] when starting a new session.
///
/// Finding reference: L22-06 (Voice coaching parcial).
final class HydrationVoiceTrigger {
  /// Silent warmup window (ms of moving time) before the first prompt.
  final int warmupMs;

  /// Interval between prompts after warmup (ms of moving time).
  final int intervalMs;

  /// Locale-aware formatter supplying the reminder phrase.
  final AudioCueFormatter formatter;

  int _lastFiredMovingMs = -1;

  HydrationVoiceTrigger({
    required this.formatter,
    this.warmupMs = 20 * 60 * 1000,
    this.intervalMs = 20 * 60 * 1000,
  })  : assert(warmupMs >= 0, 'warmupMs must be non-negative'),
        assert(intervalMs > 0, 'intervalMs must be positive');

  /// Exposed for tests.
  int get lastFiredMovingMs => _lastFiredMovingMs;

  /// Reset for a new session.
  void reset() {
    _lastFiredMovingMs = -1;
  }

  /// Evaluate [metrics] for the current tick.
  AudioEventEntity? evaluate(
    WorkoutMetricsEntity metrics, {
    bool isPaused = false,
  }) {
    if (isPaused) return null;
    final movingMs = metrics.movingMs;
    if (movingMs < warmupMs) return null;

    final int nextEligibleMs;
    if (_lastFiredMovingMs < 0) {
      nextEligibleMs = warmupMs;
    } else {
      nextEligibleMs = _lastFiredMovingMs + intervalMs;
    }
    if (movingMs < nextEligibleMs) return null;

    _lastFiredMovingMs = movingMs;

    return AudioEventEntity(
      type: AudioEventType.custom,
      priority: 13,
      payload: {
        'text': formatter.hydrationReminder(),
        'action': 'HYDRATION',
      },
    );
  }
}
