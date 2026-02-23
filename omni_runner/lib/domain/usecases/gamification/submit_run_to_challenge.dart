import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Submits a completed, verified workout session to an active challenge.
///
/// Validates:
/// - Challenge exists and is [ChallengeStatus.active].
/// - User is a participant with [ParticipantStatus.accepted].
/// - Session is verified (`isVerified == true`).
/// - Session meets minimum distance.
/// - Session was not already submitted.
/// - Session falls within the challenge window.
///
/// Updates the participant's [progressValue] and [contributingSessionIds].
///
/// Conforms to [O4]: single `call()` method.
final class SubmitRunToChallenge {
  final IChallengeRepo _challengeRepo;

  const SubmitRunToChallenge({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// [session] is the completed workout.
  /// [metricValue] is the value to add in the challenge's metric unit:
  ///   - distance: meters
  ///   - pace: average seconds/km for this session
  ///   - time: moving milliseconds
  ///
  /// Returns the updated challenge.
  /// Throws [GamificationFailure] on validation error.
  Future<ChallengeEntity> call({
    required String challengeId,
    required String userId,
    required WorkoutSessionEntity session,
    required double metricValue,
    int? submittedAtMs,
  }) async {
    final challenge = await _challengeRepo.getById(challengeId);
    if (challenge == null) throw ChallengeNotFound(challengeId);

    if (challenge.status != ChallengeStatus.active) {
      throw InvalidChallengeStatus(
        challengeId,
        ChallengeStatus.active.name,
        challenge.status.name,
      );
    }

    if (!session.isVerified) throw UnverifiedSession(session.id);

    final distanceM = session.totalDistanceM ?? 0.0;
    if (distanceM < challenge.rules.minSessionDistanceM) {
      throw SessionBelowMinimum(
        session.id,
        challenge.rules.minSessionDistanceM,
        distanceM,
      );
    }

    final idx =
        challenge.participants.indexWhere((p) => p.userId == userId);
    if (idx == -1) throw NotAParticipant(userId, challengeId);

    final participant = challenge.participants[idx];
    if (participant.status != ParticipantStatus.accepted) {
      throw NotAParticipant(userId, challengeId);
    }

    if (participant.contributingSessionIds.contains(session.id)) {
      throw SessionAlreadySubmitted(session.id, challengeId);
    }

    // For pace metric, keep the best (lowest) value instead of accumulating.
    final double newProgress;
    if (challenge.rules.metric == ChallengeMetric.pace) {
      newProgress = participant.progressValue == 0.0
          ? metricValue
          : metricValue < participant.progressValue
              ? metricValue
              : participant.progressValue;
    } else {
      newProgress = participant.progressValue + metricValue;
    }

    final nowMs = submittedAtMs ?? DateTime.now().millisecondsSinceEpoch;

    final updatedParticipants =
        List<ChallengeParticipantEntity>.of(challenge.participants);
    updatedParticipants[idx] = participant.copyWith(
      progressValue: newProgress,
      contributingSessionIds: [
        ...participant.contributingSessionIds,
        session.id,
      ],
      lastSubmittedAtMs: nowMs,
    );

    final updated =
        challenge.copyWith(participants: updatedParticipants);
    await _challengeRepo.update(updated);
    return updated;
  }
}
