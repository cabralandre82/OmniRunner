import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';

/// Fires a periodic [AudioEventType.timeAnnouncement] every [intervalMs]
/// of **moving** time (pauses excluded).
///
/// Rules:
/// - Default interval: 5 minutes (300 000 ms).
/// - Does NOT fire when [isPaused] is true.
/// - Tracks the last announced interval to prevent duplicates.
///
/// Stateful — call [reset] when starting a new session.
final class TimeVoiceTrigger {
  /// Interval in milliseconds between announcements.
  final int intervalMs;

  int _lastAnnouncedInterval = 0;

  TimeVoiceTrigger({this.intervalMs = 300000});

  /// Reset internal state for a new session.
  void reset() => _lastAnnouncedInterval = 0;

  /// Exposed for testing.
  int get lastAnnouncedInterval => _lastAnnouncedInterval;

  /// Evaluate [metrics] and return an event if a new time interval
  /// boundary has been crossed, or `null` otherwise.
  ///
  /// [isPaused] must be `true` when the session is paused — the
  /// trigger will not fire regardless of elapsed time.
  ///
  /// Payload keys:
  /// - `elapsedMin` (int): minutes of moving time reached
  /// - `distanceKm` (double): total distance so far (km)
  /// - `paceFormatted` (String): current pace, if available
  AudioEventEntity? evaluate(
    WorkoutMetricsEntity metrics, {
    bool isPaused = false,
  }) {
    if (isPaused) return null;

    final currentInterval = metrics.movingMs ~/ intervalMs;
    if (currentInterval <= 0 || currentInterval <= _lastAnnouncedInterval) {
      return null;
    }

    _lastAnnouncedInterval = currentInterval;

    final elapsedMin = (currentInterval * intervalMs) ~/ 60000;
    final distKm =
        (metrics.totalDistanceM / 10.0).roundToDouble() / 100.0;

    final payload = <String, Object>{
      'elapsedMin': elapsedMin,
      'distanceKm': distKm,
    };

    final pace = metrics.currentPaceSecPerKm;
    if (pace != null && pace > 0 && !pace.isNaN && !pace.isInfinite) {
      final totalSec = pace.round();
      final min = totalSec ~/ 60;
      final sec = totalSec % 60;
      payload['paceFormatted'] =
          '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }

    return AudioEventEntity(
      type: AudioEventType.timeAnnouncement,
      priority: 12,
      payload: payload,
    );
  }
}
