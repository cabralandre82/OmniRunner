import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';

/// A complete workout session containing metadata and GPS route.
///
/// Immutable value object. No logic. No behavior.
/// This is the core aggregate root of the domain.
final class WorkoutSessionEntity extends Equatable {
  /// Unique identifier for this session (UUID v4).
  final String id;

  /// Owner user ID. Null if not yet synced / no auth.
  final String? userId;

  /// Current status of the workout session.
  final WorkoutStatus status;

  /// Start time in milliseconds since Unix epoch (UTC).
  final int startTimeMs;

  /// End time in milliseconds since Unix epoch (UTC). Null if still active.
  final int? endTimeMs;

  /// Total accumulated distance in meters (filtered). Null if not computed.
  final double? totalDistanceM;

  /// Ordered list of GPS points captured during the session.
  final List<LocationPointEntity> route;

  /// ID of the ghost session this run was compared against. Null if no ghost.
  final String? ghostSessionId;

  /// Whether this session passed anti-cheat verification. Defaults to true.
  final bool isVerified;

  /// Human-readable integrity flags raised during verification.
  ///
  /// Empty list = no issues detected. Examples:
  /// `"SPEED_EXCEEDED"`, `"TELEPORT_DETECTED"`, `"TOO_FEW_POINTS"`.
  final List<String> integrityFlags;

  /// Whether this session has been synced to the backend. Defaults to false.
  final bool isSynced;

  /// Average heart rate in BPM. Null if no HR data was collected.
  final int? avgBpm;

  /// Maximum heart rate in BPM. Null if no HR data was collected.
  final int? maxBpm;

  const WorkoutSessionEntity({
    required this.id,
    this.userId,
    required this.status,
    required this.startTimeMs,
    this.endTimeMs,
    this.totalDistanceM,
    required this.route,
    this.ghostSessionId,
    this.isVerified = true,
    this.integrityFlags = const [],
    this.isSynced = false,
    this.avgBpm,
    this.maxBpm,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        status,
        startTimeMs,
        endTimeMs,
        totalDistanceM,
        route,
        ghostSessionId,
        isVerified,
        integrityFlags,
        isSynced,
        avgBpm,
        maxBpm,
      ];
}
