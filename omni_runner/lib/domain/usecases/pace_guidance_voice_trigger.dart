import 'package:omni_runner/domain/entities/audio_event_entity.dart';

/// The current relationship between the athlete's live pace and the
/// workout's target pace band.
///
/// - [onTarget]: pace is inside `[targetMin, targetMax]` sec/km.
/// - [tooFast]: pace is below `targetMin` (i.e. faster than allowed).
/// - [tooSlow]: pace is above `targetMax` (i.e. slower than allowed).
enum PaceGuidanceState {
  onTarget,
  tooFast,
  tooSlow,
}

extension PaceGuidanceStateWire on PaceGuidanceState {
  /// Stable snake_case string used as the `state` payload key. Kept
  /// aligned with the L22-04 runbook — renaming is a breaking change
  /// for TTS catalogue consumers.
  String get wire {
    switch (this) {
      case PaceGuidanceState.onTarget:
        return 'on_target';
      case PaceGuidanceState.tooFast:
        return 'too_fast';
      case PaceGuidanceState.tooSlow:
        return 'too_slow';
    }
  }
}

/// Emits [AudioEventType.paceAlert] when the athlete's live pace drifts
/// outside the workout's prescribed target band, and a single
/// reinforcement cue ("on_target") when they come back into the band.
///
/// **Why this is not built on top of [AudioEventType.distanceAnnouncement]:**
/// the per-km announcement (see `VoiceTriggers`) fires at most once every
/// 1 km — a beginner can already be "burned out" inside 5 minutes. The
/// finding L22-04 is specifically about *live, in-session* feedback:
/// "amador começa muito rápido e produto não fala durante". This trigger
/// evaluates every telemetry tick and reacts in seconds.
///
/// **Hysteresis:** a state change is only confirmed after [confirmCount]
/// consecutive readings in the new bucket. This prevents fluttering TTS
/// during natural pace oscillation (GPS jitter, brief uphill, etc.).
///
/// **Cooldown:** after emitting an alert, subsequent *same-state* alerts
/// are suppressed until [cooldownMs] has elapsed since the last alert —
/// even if confirmCount is met again. This avoids a runner hearing
/// "desacelere" every 5 seconds when they simply cannot slow down.
///
/// **Deadband:** to avoid nagging at band edges we require the
/// deviation from the target edge (targetMin for tooFast, targetMax for
/// tooSlow) to exceed [deadbandSec] seconds per km before a reading
/// counts as "outside". `onTarget` is always the interval
/// `[targetMin, targetMax]` inclusive — the deadband only affects how
/// quickly we decide we are *outside* the band.
///
/// **Reinforcement:** an `onTarget` cue is emitted at most once per
/// transition back into the band, so the runner hears "você está no
/// ritmo ideal" exactly when it is informative, not continuously.
///
/// Stateful — call [reset] when starting a new session.
///
/// This class is pure Dart. It does **not** speak, log, or touch
/// `flutter_tts`; it only decides when a cue should be emitted. The
/// [AudioCueFormatter] / [AudioCoachRepo] in the app layer turn the
/// resulting [AudioEventEntity] into a locale-aware spoken phrase.
final class PaceGuidanceVoiceTrigger {
  /// Number of consecutive readings in a new state before we fire.
  /// Default 3 ≈ 3 ticks (≈3 s at 1 Hz) — matches [HrZoneVoiceTrigger].
  final int confirmCount;

  /// Minimum milliseconds between two *same-state* alerts. Does not
  /// apply across state transitions: if we fire `too_fast` and the
  /// athlete immediately slows into the band we will still emit
  /// `on_target` once. Default 30 s.
  final int cooldownMs;

  /// Seconds per km of slack around the target band before a reading
  /// counts as outside. Keeps short GPS spikes silent. Default 5 s/km.
  final int deadbandSec;

  PaceGuidanceState _currentState = PaceGuidanceState.onTarget;
  PaceGuidanceState _pendingState = PaceGuidanceState.onTarget;
  int _pendingCount = 0;
  int _lastAlertMs = 0;
  bool _hasEmittedAlertOnce = false;

  PaceGuidanceVoiceTrigger({
    this.confirmCount = 3,
    this.cooldownMs = 30000,
    this.deadbandSec = 5,
  })  : assert(confirmCount >= 1, 'confirmCount must be >= 1'),
        assert(cooldownMs >= 0, 'cooldownMs must be >= 0'),
        assert(deadbandSec >= 0, 'deadbandSec must be >= 0');

  /// Currently confirmed state.
  PaceGuidanceState get currentState => _currentState;

  /// Reset state for a new session.
  void reset() {
    _currentState = PaceGuidanceState.onTarget;
    _pendingState = PaceGuidanceState.onTarget;
    _pendingCount = 0;
    _lastAlertMs = 0;
    _hasEmittedAlertOnce = false;
  }

  /// Evaluate a new pace reading against the workout's target band and
  /// return a pace guidance cue if one is due, or `null` otherwise.
  ///
  /// Inputs:
  /// - [currentPaceSecPerKm]: live pace. If `null`, `NaN`, infinite or
  ///   `<= 0`, the tick is ignored (returns `null`, no state change).
  /// - [targetPaceMinSecPerKm] / [targetPaceMaxSecPerKm]: the prescribed
  ///   target band. Both must be positive and `min <= max`; otherwise
  ///   the guard is considered inactive and this returns `null`.
  /// - [timestampMs]: monotonic milliseconds used for cooldown. The
  ///   caller is free to use `DateTime.now().millisecondsSinceEpoch`
  ///   or a session-local clock — this trigger never compares it to
  ///   wall-clock time.
  ///
  /// Payload keys on the returned [AudioEventEntity]:
  /// - `state`: `'too_fast'` | `'too_slow'` | `'on_target'` (snake_case,
  ///   stable contract with the TTS catalogue).
  /// - `deviationSec` (int): unsigned seconds/km beyond the target
  ///   edge. `0` for `on_target`.
  /// - `currentPaceSecPerKm` (int): rounded current pace.
  /// - `targetMinSecPerKm` / `targetMaxSecPerKm` (int): echoed target
  ///   band, so the TTS layer can render without re-threading plan
  ///   state.
  AudioEventEntity? evaluate({
    required double? currentPaceSecPerKm,
    required int? targetPaceMinSecPerKm,
    required int? targetPaceMaxSecPerKm,
    required int timestampMs,
  }) {
    // Guard degenerate inputs — keep the trigger silent rather than
    // surfacing garbage cues. A workout without a target band (e.g. a
    // free run) simply opts out of pace guidance.
    final pace = currentPaceSecPerKm;
    if (pace == null || pace.isNaN || pace.isInfinite || pace <= 0) {
      return null;
    }
    if (targetPaceMinSecPerKm == null || targetPaceMaxSecPerKm == null) {
      return null;
    }
    if (targetPaceMinSecPerKm <= 0 || targetPaceMaxSecPerKm <= 0) {
      return null;
    }
    if (targetPaceMinSecPerKm > targetPaceMaxSecPerKm) {
      return null;
    }

    final reading = _classify(
      pace: pace,
      targetMin: targetPaceMinSecPerKm,
      targetMax: targetPaceMaxSecPerKm,
    );

    // Building hysteresis towards a new state.
    if (reading == _currentState) {
      _pendingState = _currentState;
      _pendingCount = 0;
      return null;
    }
    if (reading == _pendingState) {
      _pendingCount++;
    } else {
      _pendingState = reading;
      _pendingCount = 1;
    }

    // Not enough consecutive readings yet.
    if (_pendingCount < confirmCount) return null;

    // Confirmed state change.
    _currentState = reading;
    _pendingState = reading;
    _pendingCount = 0;

    // Cooldown applies only to *alert* cues (tooFast / tooSlow). The
    // on_target reinforcement is always delivered on transition back
    // into the band — the finding L22-04 explicitly asks the coach to
    // *confirm* when the runner is on pace ("FC zona 3, ideal.
    // Mantenha.") and silencing it under cooldown would defeat the
    // purpose.
    if (reading != PaceGuidanceState.onTarget &&
        _hasEmittedAlertOnce &&
        (timestampMs - _lastAlertMs) < cooldownMs) {
      return null;
    }

    if (reading != PaceGuidanceState.onTarget) {
      _lastAlertMs = timestampMs;
      _hasEmittedAlertOnce = true;
    }

    final deviation = _deviationSec(
      state: reading,
      pace: pace,
      targetMin: targetPaceMinSecPerKm,
      targetMax: targetPaceMaxSecPerKm,
    );

    return AudioEventEntity(
      type: AudioEventType.paceAlert,
      priority: reading == PaceGuidanceState.onTarget ? 11 : 6,
      payload: {
        'state': reading.wire,
        'deviationSec': deviation,
        'currentPaceSecPerKm': pace.round(),
        'targetMinSecPerKm': targetPaceMinSecPerKm,
        'targetMaxSecPerKm': targetPaceMaxSecPerKm,
      },
    );
  }

  PaceGuidanceState _classify({
    required double pace,
    required int targetMin,
    required int targetMax,
  }) {
    if (pace < targetMin - deadbandSec) return PaceGuidanceState.tooFast;
    if (pace > targetMax + deadbandSec) return PaceGuidanceState.tooSlow;
    return PaceGuidanceState.onTarget;
  }

  int _deviationSec({
    required PaceGuidanceState state,
    required double pace,
    required int targetMin,
    required int targetMax,
  }) {
    switch (state) {
      case PaceGuidanceState.tooFast:
        return (targetMin - pace).round().abs();
      case PaceGuidanceState.tooSlow:
        return (pace - targetMax).round().abs();
      case PaceGuidanceState.onTarget:
        return 0;
    }
  }
}
