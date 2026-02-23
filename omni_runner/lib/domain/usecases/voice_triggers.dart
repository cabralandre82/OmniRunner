import 'package:omni_runner/domain/entities/audio_event_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';

/// Evaluates workout metrics and emits audio coaching events
/// when trigger conditions are met.
///
/// Currently supports:
/// - **KM trigger**: fires [AudioEventType.distanceAnnouncement] each time
///   [WorkoutMetricsEntity.totalDistanceM] crosses a full-kilometer boundary.
///
/// Stateful: tracks [_lastAnnouncedKm] to prevent duplicate announcements.
/// Call [reset] when starting a new session.
final class VoiceTriggers {
  /// Distance interval in meters between announcements.
  final double intervalM;

  int _lastAnnouncedKm = 0;

  VoiceTriggers({this.intervalM = 1000.0});

  /// Reset internal state. Call when a new session starts.
  void reset() => _lastAnnouncedKm = 0;

  /// The last full-km boundary that was announced.
  int get lastAnnouncedKm => _lastAnnouncedKm;

  /// Evaluate [metrics] and return an [AudioEventEntity] if a new
  /// full-kilometer boundary has been crossed, or `null` otherwise.
  ///
  /// The returned event carries payload keys consumed by the TTS formatter:
  /// - `distanceKm` (double): the km milestone just reached
  /// - `paceFormatted` (String): formatted current pace, if available
  /// - `paceSecPerKm` (double): raw pace value, if available
  AudioEventEntity? evaluate(WorkoutMetricsEntity metrics) {
    final currentKm = (metrics.totalDistanceM / intervalM).floor();
    if (currentKm <= 0 || currentKm <= _lastAnnouncedKm) return null;

    _lastAnnouncedKm = currentKm;

    final payload = <String, Object>{
      'distanceKm': currentKm * (intervalM / 1000.0),
    };

    final pace = metrics.currentPaceSecPerKm;
    if (pace != null && pace > 0 && !pace.isNaN && !pace.isInfinite) {
      final totalSec = pace.round();
      final min = totalSec ~/ 60;
      final sec = totalSec % 60;
      final mm = min.toString().padLeft(2, '0');
      final ss = sec.toString().padLeft(2, '0');
      payload['paceFormatted'] = '$mm:$ss';
      payload['paceSecPerKm'] = pace;
    }

    return AudioEventEntity(
      type: AudioEventType.distanceAnnouncement,
      priority: 10,
      payload: payload,
    );
  }
}
