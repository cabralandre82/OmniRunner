import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// A recorded workout session used as a "ghost" for comparison.
///
/// The ghost represents a previous run that the runner can race against.
/// During a live workout, the ghost's position is interpolated based on
/// elapsed time to show where the runner was at this point in the
/// original session.
///
/// Immutable value object. No logic. No behavior.
final class GhostSessionEntity extends Equatable {
  /// Unique identifier of the original session this ghost was created from.
  final String sessionId;

  /// Ordered list of GPS points from the original session.
  /// Used for interpolation during ghost replay.
  final List<LocationPointEntity> route;

  /// Start time of the original session in milliseconds since epoch (UTC).
  final int startTimeMs;

  /// Total duration of the original session in milliseconds.
  /// Calculated as last point timestamp - first point timestamp.
  final int durationMs;

  const GhostSessionEntity({
    required this.sessionId,
    required this.route,
    required this.startTimeMs,
    required this.durationMs,
  });

  @override
  List<Object?> get props => [
        sessionId,
        route,
        startTimeMs,
        durationMs,
      ];
}
