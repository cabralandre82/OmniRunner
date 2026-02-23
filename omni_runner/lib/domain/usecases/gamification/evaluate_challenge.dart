import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/challenge_evaluator.dart';

/// Evaluates a completed challenge window and produces results.
///
/// Transitions the challenge to [ChallengeStatus.completing], delegates
/// ranking/reward logic to [ChallengeEvaluator], and persists the
/// [ChallengeResultEntity].
///
/// Does NOT distribute Coins — that is [SettleChallenge]'s job.
/// This separation allows review before settlement.
///
/// Conforms to [O4]: single `call()` method.
final class EvaluateChallenge {
  final IChallengeRepo _challengeRepo;
  final ChallengeEvaluator _evaluator;

  const EvaluateChallenge({
    required IChallengeRepo challengeRepo,
    ChallengeEvaluator evaluator = const ChallengeEvaluator(),
  })  : _challengeRepo = challengeRepo,
        _evaluator = evaluator;

  /// [nowMs] is the current timestamp.
  /// Returns the finalized [ChallengeResultEntity].
  /// Throws [GamificationFailure] on validation error.
  Future<ChallengeResultEntity> call({
    required String challengeId,
    required int nowMs,
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

    await _challengeRepo.update(
      challenge.copyWith(status: ChallengeStatus.completing),
    );

    final results = _evaluator.evaluate(challenge);

    var totalCoins = 0;
    for (final r in results) {
      totalCoins += r.coinsEarned;
    }

    final result = ChallengeResultEntity(
      challengeId: challengeId,
      metric: challenge.rules.metric,
      results: results,
      totalCoinsDistributed: totalCoins,
      calculatedAtMs: nowMs,
    );

    await _challengeRepo.saveResult(result);
    return result;
  }
}
