import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

/// Reason a session was rejected for a challenge.
enum BindingRejectionReason {
  /// Session status is not [WorkoutStatus.completed].
  notCompleted,

  /// Session failed anti-cheat verification.
  notVerified,

  /// Session distance is below [ChallengeRulesEntity.minSessionDistanceM].
  belowMinDistance,

  /// Session timestamp falls outside the challenge window.
  outsideWindow,

  /// Session was already submitted to this challenge.
  alreadySubmitted,

  /// Challenge requires strict anti-cheat (HR) but session has no HR data.
  missingHeartRate,

  /// Session distance is below the challenge target (e.g. ran 8 km in a 10 km challenge).
  belowTargetDistance,

  /// Submit to challenge failed due to a transient error (I/O, DB).
  submitFailed,
}

/// Snapshot of the validation result when binding a workout session
/// to a challenge.
///
/// Created by [PostSessionChallengeDispatcher] after a session finishes.
/// Records WHY a session was accepted or rejected for each active
/// challenge, providing a complete audit trail.
///
/// Immutable value object. No logic. No behavior.
final class ChallengeRunBindingEntity extends Equatable {
  /// The workout session ID.
  final String sessionId;

  /// The challenge this binding applies to.
  final String challengeId;

  /// The user who ran the session.
  final String userId;

  /// Whether the session was accepted into the challenge.
  final bool accepted;

  /// If rejected, the reason. Null if accepted.
  final BindingRejectionReason? rejectionReason;

  /// The progress value extracted from the session for this challenge.
  ///
  /// - fastestAtDistance: elapsed seconds
  /// - mostDistance / collectiveDistance: total meters
  /// - bestPaceAtDistance: avg seconds/km
  ///
  /// Null if rejected before extraction.
  final double? metricValue;

  /// Session distance in meters at bind time (snapshot).
  final double sessionDistanceM;

  /// Whether the session was verified at bind time.
  final bool sessionVerified;

  /// Integrity flags at bind time (snapshot).
  final List<String> sessionIntegrityFlags;

  /// Whether the session had HR data (relevant for strict policy).
  final bool sessionHadHr;

  /// When this binding was evaluated (ms since epoch, UTC).
  final int evaluatedAtMs;

  const ChallengeRunBindingEntity({
    required this.sessionId,
    required this.challengeId,
    required this.userId,
    required this.accepted,
    this.rejectionReason,
    this.metricValue,
    required this.sessionDistanceM,
    required this.sessionVerified,
    this.sessionIntegrityFlags = const [],
    required this.sessionHadHr,
    required this.evaluatedAtMs,
  });

  @override
  List<Object?> get props => [
        sessionId,
        challengeId,
        userId,
        accepted,
        rejectionReason,
        metricValue,
        sessionDistanceM,
        sessionVerified,
        sessionIntegrityFlags,
        sessionHadHr,
        evaluatedAtMs,
      ];
}
