import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Cancels a pending challenge. Only the creator may cancel.
///
/// Validates:
/// - Challenge exists and is [ChallengeStatus.pending].
/// - Caller is the creator.
///
/// No Coins are gained or lost on cancellation
/// (per GAMIFICATION_POLICY.md §4.1).
///
/// Conforms to [O4]: single `call()` method.
final class CancelChallenge {
  final IChallengeRepo _challengeRepo;

  const CancelChallenge({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// Throws [GamificationFailure] on validation error.
  Future<void> call({
    required String challengeId,
    required String userId,
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

    if (challenge.creatorUserId != userId) {
      throw NotChallengeCreator(userId, challengeId);
    }

    await _challengeRepo.update(
      challenge.copyWith(status: ChallengeStatus.cancelled),
    );
  }
}
