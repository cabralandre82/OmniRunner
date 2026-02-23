import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// An invited participant accepts the challenge.
///
/// Validates:
/// - Challenge exists and is [ChallengeStatus.pending].
/// - User is a participant with [ParticipantStatus.invited].
///
/// Conforms to [O4]: single `call()` method.
final class JoinChallenge {
  final IChallengeRepo _challengeRepo;

  const JoinChallenge({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// Returns the updated challenge.
  /// Throws [GamificationFailure] on validation error.
  Future<ChallengeEntity> call({
    required String challengeId,
    required String userId,
    required int respondedAtMs,
  }) async {
    final challenge = await _challengeRepo.getById(challengeId);
    if (challenge == null) throw ChallengeNotFound(challengeId);

    if (challenge.status != ChallengeStatus.pending) {
      throw InvalidChallengeStatus(
        challengeId,
        ChallengeStatus.pending.name,
        challenge.status.name,
      );
    }

    final idx =
        challenge.participants.indexWhere((p) => p.userId == userId);
    if (idx == -1) throw NotAParticipant(userId, challengeId);

    final participant = challenge.participants[idx];
    if (participant.status != ParticipantStatus.invited) {
      throw AlreadyParticipant(userId, challengeId);
    }

    final updatedParticipants =
        List<ChallengeParticipantEntity>.of(challenge.participants);
    updatedParticipants[idx] = participant.copyWith(
      status: ParticipantStatus.accepted,
      respondedAtMs: respondedAtMs,
    );

    final updated =
        challenge.copyWith(participants: updatedParticipants);
    await _challengeRepo.update(updated);
    return updated;
  }
}
