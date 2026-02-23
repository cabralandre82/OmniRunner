import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';

/// States for [TrackingBloc].
///
/// Sealed class hierarchy for exhaustive handling in UI.
sealed class TrackingState extends Equatable {
  const TrackingState();

  @override
  List<Object?> get props => [];
}

/// Initial state — no checks performed yet.
final class TrackingIdle extends TrackingState {
  const TrackingIdle();
}

/// Location permission or service is not available.
///
/// [message] describes the reason for UI display.
/// [canRetry] indicates if the user can re-request permission.
final class TrackingNeedsPermission extends TrackingState {
  final String message;
  final bool canRetry;

  const TrackingNeedsPermission({
    required this.message,
    this.canRetry = true,
  });

  @override
  List<Object?> get props => [message, canRetry];
}

/// GPS is actively tracking — collecting location points.
///
/// [ghostDeltaM] signed distance delta to ghost (meters). null = no ghost.
/// [ghostPosition] interpolated ghost location for map rendering.
/// [currentBpm] latest heart rate from BLE sensor. null = no HR source.
/// [hrConnectionState] current BLE HR connection state for UI display.
/// [gpsLost] true when GPS stream closed unexpectedly; reconnection in progress.
/// [challengeId] non-null when running in challenge mode.
/// [challengeOpponentName] opponent display name for overlay rendering.
/// [challengeTargetM] target distance for the challenge (meters).
final class TrackingActive extends TrackingState {
  final List<LocationPointEntity> points;
  final WorkoutMetricsEntity? metrics;
  final bool pauseSuggested;
  final double? ghostDeltaM;
  final LocationPointEntity? ghostPosition;
  final bool isVerified;
  final List<String> integrityFlags;
  final int? currentBpm;
  final String? hrConnectionState;
  final bool gpsLost;
  final int? ghostDurationMs;
  final double? ghostTotalDistanceM;
  final String? challengeId;
  final String? challengeOpponentUserId;
  final String? challengeOpponentName;
  final double? challengeTargetM;

  const TrackingActive({
    required this.points,
    this.metrics,
    this.pauseSuggested = false,
    this.ghostDeltaM,
    this.ghostPosition,
    this.isVerified = true,
    this.integrityFlags = const [],
    this.currentBpm,
    this.hrConnectionState,
    this.gpsLost = false,
    this.ghostDurationMs,
    this.ghostTotalDistanceM,
    this.challengeId,
    this.challengeOpponentUserId,
    this.challengeOpponentName,
    this.challengeTargetM,
  });

  int get pointsCount => points.length;

  bool get inChallengeMode => challengeId != null;

  @override
  List<Object?> get props =>
      [points, metrics, pauseSuggested, ghostDeltaM, ghostPosition, isVerified, integrityFlags, currentBpm, hrConnectionState, gpsLost, ghostDurationMs, ghostTotalDistanceM, challengeId, challengeOpponentUserId, challengeOpponentName, challengeTargetM];
}

/// An unrecoverable error occurred during tracking.
final class TrackingError extends TrackingState {
  final String message;

  const TrackingError({required this.message});

  @override
  List<Object?> get props => [message];
}
