import 'package:equatable/equatable.dart';

/// Calculated metrics for a workout session.
///
/// Immutable value object. No logic. No behavior.
/// Produced by use cases, consumed by presentation.
///
/// Conventions (per PHASE 03 rules):
/// - Distance: meters (double)
/// - Time: milliseconds (int)
/// - Pace: seconds per km (double) internally; UI formats as min:sec/km
final class WorkoutMetricsEntity extends Equatable {
  /// Total accumulated distance in meters.
  /// Filtered by accuracy and drift thresholds.
  final double totalDistanceM;

  /// Total elapsed time in milliseconds (wall clock: start to now/end).
  final int elapsedMs;

  /// Time spent actually moving in milliseconds.
  /// Excludes pauses and stationary periods.
  final int movingMs;

  /// Current instantaneous pace in seconds per kilometer.
  /// Null if not enough data or currently stationary.
  final double? currentPaceSecPerKm;

  /// Average pace in seconds per kilometer over the entire workout.
  /// Null if distance is zero.
  final double? avgPaceSecPerKm;

  /// Total number of GPS points recorded (including filtered ones).
  final int pointsCount;

  /// Current (most recent) heart rate in BPM. Null if no HR source active.
  final int? currentBpm;

  /// Average heart rate in BPM over the session. Null if no HR data.
  final int? avgBpm;

  /// Maximum heart rate in BPM during the session. Null if no HR data.
  final int? maxBpm;

  const WorkoutMetricsEntity({
    required this.totalDistanceM,
    required this.elapsedMs,
    required this.movingMs,
    this.currentPaceSecPerKm,
    this.avgPaceSecPerKm,
    required this.pointsCount,
    this.currentBpm,
    this.avgBpm,
    this.maxBpm,
  });

  @override
  List<Object?> get props => [
        totalDistanceM,
        elapsedMs,
        movingMs,
        currentPaceSecPerKm,
        avgPaceSecPerKm,
        pointsCount,
        currentBpm,
        avgBpm,
        maxBpm,
      ];
}
