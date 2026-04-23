import 'package:omni_runner/domain/entities/audio_event_entity.dart';

/// Emits a pre-start countdown of configurable length.
///
/// Classic "5, 4, 3, 2, 1, GO!" pattern but parametric:
/// [countdownSec] defines the total length (default 5 seconds).
/// Evaluate each tick with the milliseconds elapsed since the
/// countdown started. The trigger fires exactly once per second
/// crossed, including the final `GO!` at zero.
///
/// Priority 2 (lower = more urgent). Countdown cues MUST interrupt
/// whatever is speaking because the runner is waiting on them.
///
/// Stateful — call [reset] before each new countdown.
///
/// Finding reference: L22-06 (Voice coaching parcial).
final class CountdownVoiceTrigger {
  /// Total countdown length in whole seconds. Must be > 0.
  final int countdownSec;

  int _lastAnnouncedRemaining;

  CountdownVoiceTrigger({this.countdownSec = 5})
      : assert(countdownSec > 0, 'countdownSec must be positive'),
        _lastAnnouncedRemaining = countdownSec + 1;

  /// Reset state before a new countdown. Must be called every time
  /// the user arms the timer, otherwise the first [evaluate] of the
  /// second countdown short-circuits silently.
  void reset() {
    _lastAnnouncedRemaining = countdownSec + 1;
  }

  /// Exposed for tests.
  int get lastAnnouncedRemaining => _lastAnnouncedRemaining;

  /// Evaluate the countdown at [elapsedMs] since countdown armed.
  ///
  /// Returns an [AudioEventEntity] when a new whole-second boundary
  /// is crossed, `null` otherwise (sub-second tick, already-announced
  /// second, or countdown already finished).
  ///
  /// Payload keys:
  /// - `value` (int): seconds remaining (countdownSec..0; 0 means GO!)
  AudioEventEntity? evaluate(int elapsedMs) {
    if (elapsedMs < 0) return null;
    final elapsedSec = elapsedMs ~/ 1000;
    if (elapsedSec > countdownSec) return null;

    final remaining = countdownSec - elapsedSec;
    if (remaining >= _lastAnnouncedRemaining) return null;

    _lastAnnouncedRemaining = remaining;

    return AudioEventEntity(
      type: AudioEventType.countdown,
      priority: 2,
      payload: {'value': remaining},
    );
  }
}
