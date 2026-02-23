import 'package:omni_runner/domain/entities/audio_event_entity.dart';

/// Detects when the runner overtakes the ghost (or vice-versa) and
/// emits an [AudioEventEntity].
///
/// Sign convention (from [CalculateGhostDelta]):
///   positive deltaM → runner is **ahead** of ghost
///   negative deltaM → runner is **behind** ghost
///
/// Fires:
/// - `GHOST_PASSED`    — runner went from behind to ahead
/// - `GHOST_PASSED_BY` — runner went from ahead to behind
///
/// Hysteresis: a sign change is only acknowledged when the absolute
/// delta exceeds [minDeltaM] (default 5 m), preventing rapid toggling
/// when runner and ghost are neck-and-neck.
///
/// Stateful — call [reset] when starting a new session.
final class GhostVoiceTrigger {
  /// Minimum absolute delta (meters) to confirm a sign flip.
  final double minDeltaM;

  /// Last confirmed sign: -1 = behind, 0 = unknown, 1 = ahead.
  int _lastSign = 0;

  GhostVoiceTrigger({this.minDeltaM = 5.0});

  /// Reset internal state for a new session.
  void reset() => _lastSign = 0;

  /// Exposed for testing.
  int get lastSign => _lastSign;

  /// Evaluate the current [ghostDeltaM].
  ///
  /// Returns an event on sign flip, `null` otherwise.
  AudioEventEntity? evaluate(double? ghostDeltaM) {
    if (ghostDeltaM == null) return null;

    // Determine sign with hysteresis dead-zone.
    final int currentSign;
    if (ghostDeltaM > minDeltaM) {
      currentSign = 1;
    } else if (ghostDeltaM < -minDeltaM) {
      currentSign = -1;
    } else {
      return null; // inside dead zone — no change
    }

    if (currentSign == _lastSign) return null;

    final previous = _lastSign;
    _lastSign = currentSign;

    // First observation: just record, don't fire.
    if (previous == 0) return null;

    // Sign flip confirmed.
    if (currentSign > 0) {
      return const AudioEventEntity(
        type: AudioEventType.custom,
        priority: 8,
        payload: {
          'text': 'Você ultrapassou o fantasma!',
          'action': 'GHOST_PASSED',
        },
      );
    }
    return const AudioEventEntity(
      type: AudioEventType.custom,
      priority: 8,
      payload: {
        'text': 'O fantasma ultrapassou você!',
        'action': 'GHOST_PASSED_BY',
      },
    );
  }
}
