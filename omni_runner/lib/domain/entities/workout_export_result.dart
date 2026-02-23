import 'package:equatable/equatable.dart';

/// Result of exporting a workout to the platform health service.
///
/// Immutable value object tracking what was successfully written.
final class WorkoutExportResult extends Equatable {
  /// Whether the HKWorkout / Health Connect exercise record was created.
  final bool workoutSaved;

  /// Whether the GPS route was attached to the workout.
  ///
  /// `false` if route export failed or was skipped (e.g. no GPS points,
  /// or the `health` plugin's `writeWorkoutData` did not return a UUID
  /// needed to associate the route).
  final bool routeAttached;

  /// Number of GPS points included in the route.
  final int routePointCount;

  /// Human-readable message (error detail or success summary).
  final String message;

  const WorkoutExportResult({
    required this.workoutSaved,
    this.routeAttached = false,
    this.routePointCount = 0,
    this.message = '',
  });

  @override
  List<Object?> get props => [
        workoutSaved,
        routeAttached,
        routePointCount,
        message,
      ];
}
