import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/hr_zone.dart';

/// Emits [AudioEventType.heartRateAlert] when the user's HR zone changes.
///
/// **Cooldown:** After emitting an alert, subsequent zone changes within
/// [cooldownMs] are suppressed to avoid spamming the runner with
/// rapid-fire TTS announcements during zone boundary oscillation.
///
/// **Hysteresis:** A zone change is only confirmed after [confirmCount]
/// consecutive readings in the new zone, reducing false triggers from
/// momentary BPM spikes.
///
/// Stateful — call [reset] when starting a new session.
final class HrZoneVoiceTrigger {
  /// Minimum milliseconds between two alerts.
  final int cooldownMs;

  /// Number of consecutive readings in a new zone before confirming.
  final int confirmCount;

  final HrZoneCalculator _calculator;

  HrZone _currentZone = HrZone.belowZones;
  HrZone _pendingZone = HrZone.belowZones;
  int _pendingCount = 0;
  int _lastAlertMs = 0;

  HrZoneVoiceTrigger({
    required HrZoneCalculator calculator,
    this.cooldownMs = 30000,
    this.confirmCount = 3,
  }) : _calculator = calculator;

  /// The currently confirmed zone.
  HrZone get currentZone => _currentZone;

  /// The underlying calculator.
  HrZoneCalculator get calculator => _calculator;

  /// Reset state for a new session.
  void reset() {
    _currentZone = HrZone.belowZones;
    _pendingZone = HrZone.belowZones;
    _pendingCount = 0;
    _lastAlertMs = 0;
  }

  /// Evaluate a new [bpm] reading at [timestampMs].
  ///
  /// Returns an [AudioEventEntity] with [AudioEventType.heartRateAlert]
  /// if a confirmed zone change occurred and cooldown has elapsed,
  /// or `null` otherwise.
  ///
  /// Payload keys:
  /// - `zone` (int): zone number (1–5)
  /// - `zoneName` (String): human-readable label
  /// - `bpm` (int): current BPM
  /// - `direction` (String): `'up'` or `'down'`
  /// - `maxHr` (int): configured max HR
  AudioEventEntity? evaluate({
    required int bpm,
    required int timestampMs,
  }) {
    final newZone = _calculator.zoneFor(bpm);

    // Same as confirmed zone — reset pending.
    if (newZone == _currentZone) {
      _pendingZone = _currentZone;
      _pendingCount = 0;
      return null;
    }

    // Building towards a new zone.
    if (newZone == _pendingZone) {
      _pendingCount++;
    } else {
      _pendingZone = newZone;
      _pendingCount = 1;
    }

    // Not enough consecutive readings yet.
    if (_pendingCount < confirmCount) return null;

    // Confirmed zone change.
    final previousZone = _currentZone;
    _currentZone = newZone;
    _pendingZone = newZone;
    _pendingCount = 0;

    // Don't alert for belowZones (not meaningful for the runner).
    if (newZone == HrZone.belowZones) return null;

    // Cooldown check.
    if (_lastAlertMs > 0 && (timestampMs - _lastAlertMs) < cooldownMs) {
      return null;
    }

    _lastAlertMs = timestampMs;

    final direction =
        newZone.number > previousZone.number ? 'up' : 'down';

    return AudioEventEntity(
      type: AudioEventType.heartRateAlert,
      priority: 7,
      payload: {
        'zone': newZone.number,
        'zoneName': newZone.label,
        'bpm': bpm,
        'direction': direction,
        'maxHr': _calculator.maxHr,
      },
    );
  }
}
