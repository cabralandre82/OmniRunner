import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/ghost_session_entity.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Events for [TrackingBloc].
///
/// Sealed class hierarchy for exhaustive handling.
sealed class TrackingEvent extends Equatable {
  const TrackingEvent();

  @override
  List<Object?> get props => [];
}

/// App has started — check permissions and service availability.
final class AppStarted extends TrackingEvent {
  const AppStarted();
}

/// User explicitly requests location permission.
final class RequestPermission extends TrackingEvent {
  const RequestPermission();
}

/// User starts GPS tracking (begin collecting points).
final class StartTracking extends TrackingEvent {
  const StartTracking();
}

/// User stops GPS tracking.
final class StopTracking extends TrackingEvent {
  const StopTracking();
}

/// App lifecycle changed (forwarded from WidgetsBindingObserver).
///
/// Used to re-check permissions on resume and handle background transitions.
final class AppLifecycleChanged extends TrackingEvent {
  final bool isResumed;

  const AppLifecycleChanged({required this.isResumed});

  @override
  List<Object?> get props => [isResumed];
}

/// A new location point was received from the GPS stream.
///
/// Dispatched internally by the stream subscription, not by the UI.
final class LocationPointReceived extends TrackingEvent {
  final LocationPointEntity point;

  const LocationPointReceived(this.point);

  @override
  List<Object?> get props => [point];
}

/// GPS stream closed (device GPS disabled, stream ended).
///
/// Dispatched internally by the stream subscription's onDone callback.
/// Triggers reconnection attempts instead of immediately stopping the session.
final class GpsStreamEnded extends TrackingEvent {
  const GpsStreamEnded();
}

/// An error occurred in the GPS stream.
///
/// Dispatched internally by the stream subscription, not by the UI.
final class LocationStreamError extends TrackingEvent {
  final String message;

  const LocationStreamError(this.message);

  @override
  List<Object?> get props => [message];
}

/// A new heart rate sample was received from BLE.
///
/// Dispatched internally by the HR stream subscription.
final class HeartRateReceived extends TrackingEvent {
  final HeartRateSample sample;

  const HeartRateReceived(this.sample);

  @override
  List<Object?> get props => [sample];
}

/// Sets (or clears) the ghost session to race against.
///
/// Dispatch before [StartTracking] to enable ghost comparison.
/// Pass `null` to disable ghost.
final class SetGhostSession extends TrackingEvent {
  final GhostSessionEntity? ghost;

  const SetGhostSession(this.ghost);

  @override
  List<Object?> get props => [ghost];
}

/// Activates challenge mode for this tracking session.
///
/// The overlay will show the opponent's relative progress.
/// Pass `null` fields to clear challenge mode.
final class SetChallengeContext extends TrackingEvent {
  final String? challengeId;
  final String? opponentUserId;
  final String? opponentName;
  final double? targetDistanceM;

  const SetChallengeContext({
    this.challengeId,
    this.opponentUserId,
    this.opponentName,
    this.targetDistanceM,
  });

  @override
  List<Object?> get props => [challengeId, opponentUserId, opponentName, targetDistanceM];
}
