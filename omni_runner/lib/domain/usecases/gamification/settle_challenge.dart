import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/ledger_service.dart';

/// Distributes entry-fee pool to winners of staked challenges.
///
/// Free challenges (entryFeeCoins == 0) produce zero coin movements.
/// Transitions the challenge to [ChallengeStatus.completed].
///
/// Delegates all coin movements to [LedgerService.creditReward],
/// which provides per-entry idempotency via (userId, refId, reason)
/// dedup — safe to retry after a mid-loop crash.
final class SettleChallenge {
  final IChallengeRepo _challengeRepo;
  final LedgerService _ledgerService;

  const SettleChallenge({
    required IChallengeRepo challengeRepo,
    required LedgerService ledgerService,
  })  : _challengeRepo = challengeRepo,
        _ledgerService = ledgerService;

  Future<void> call({
    required String challengeId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final challenge = await _challengeRepo.getById(challengeId);
    if (challenge == null) throw ChallengeNotFound(challengeId);

    if (challenge.status == ChallengeStatus.completed) return;

    if (challenge.status != ChallengeStatus.completing) {
      throw InvalidChallengeStatus(
        challengeId,
        ChallengeStatus.completing.name,
        challenge.status.name,
      );
    }

    final result =
        await _challengeRepo.getResultByChallengeId(challengeId);
    if (result == null) {
      throw InvalidChallengeStatus(
        challengeId,
        'result exists',
        'no result found',
      );
    }

    for (final pr in result.results) {
      if (pr.coinsEarned <= 0) continue;

      final reason = _reasonFor(challenge.type, pr.outcome);

      await _ledgerService.creditReward(
        userId: pr.userId,
        amount: pr.coinsEarned,
        reason: reason,
        refId: challengeId,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );
    }

    await _challengeRepo.update(
      challenge.copyWith(status: ChallengeStatus.completed),
    );
  }

  LedgerReason _reasonFor(
    ChallengeType type,
    ParticipantOutcome outcome,
  ) =>
      switch ((type, outcome)) {
        (ChallengeType.oneVsOne, ParticipantOutcome.won) =>
          LedgerReason.challengeOneVsOneWon,
        (ChallengeType.oneVsOne, ParticipantOutcome.tied) =>
          LedgerReason.challengeOneVsOneWon,
        (ChallengeType.oneVsOne, _) =>
          LedgerReason.challengeOneVsOneCompleted,
        (ChallengeType.team, ParticipantOutcome.won) =>
          LedgerReason.challengeTeamWon,
        (ChallengeType.team, _) =>
          LedgerReason.challengeGroupCompleted,
        (ChallengeType.group, _) =>
          LedgerReason.challengeGroupCompleted,
      };
}
