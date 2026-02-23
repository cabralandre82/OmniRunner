import 'package:equatable/equatable.dart';

/// Type of audio coaching event.
///
/// Each value represents a distinct category of spoken feedback
/// the audio coach can deliver during a workout.
enum AudioEventType {
  /// Periodic distance/pace update (e.g., "1 km — pace 5:30").
  distanceAnnouncement,

  /// Periodic time-based update (e.g., "10 minutes elapsed").
  timeAnnouncement,

  /// Heart-rate zone change or alert.
  heartRateAlert,

  /// Pace deviation warning (too fast / too slow).
  paceAlert,

  /// Session lifecycle event (start, pause, resume, finish).
  sessionEvent,

  /// Countdown before session starts.
  countdown,

  /// Custom / user-defined coaching cue.
  custom,
}

/// Immutable value object representing a single audio coaching event.
///
/// Carries the [type] of announcement, a [priority] (lower = more urgent,
/// 0 is highest), and an optional [payload] map with type-specific data
/// that the TTS adapter can use to build the spoken string.
final class AudioEventEntity extends Equatable {
  /// Category of this coaching event.
  final AudioEventType type;

  /// Priority level. 0 = highest (interrupt), 10 = default, 20 = low.
  /// Used by the coach to decide queuing and ducking behavior.
  final int priority;

  /// Key-value data consumed by the TTS formatter.
  ///
  /// Example for [AudioEventType.distanceAnnouncement]:
  /// ```dart
  /// {'distanceKm': 1.0, 'paceSecPerKm': 330.0}
  /// ```
  final Map<String, Object> payload;

  const AudioEventEntity({
    required this.type,
    this.priority = 10,
    this.payload = const {},
  });

  @override
  List<Object?> get props => [type, priority, payload];
}
