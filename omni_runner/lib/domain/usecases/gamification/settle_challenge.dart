import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Distributes entry-fee pool to winners of staked challenges.
///
/// Free challenges (entryFeeCoins == 0) produce zero coin movements.
/// OmniCoins are only acquired via assessoria or won in staked challenges.
///
/// Transitions the challenge to [ChallengeStatus.completed].
/// Creates one [LedgerEntryEntity] per winner reward.
/// Updates each winner's [WalletEntity].
///
/// Idempotent — checks if result already exists and challenge is
/// already completed before writing.
final class SettleChallenge {
  final IChallengeRepo _challengeRepo;
  final ILedgerRepo _ledgerRepo;
  final IWalletRepo _walletRepo;

  const SettleChallenge({
    required IChallengeRepo challengeRepo,
    required ILedgerRepo ledgerRepo,
    required IWalletRepo walletRepo,
  })  : _challengeRepo = challengeRepo,
        _ledgerRepo = ledgerRepo,
        _walletRepo = walletRepo;

  /// [uuidGenerator] provides unique IDs for ledger entries.
  /// [nowMs] is the current timestamp.
  /// Throws [GamificationFailure] on validation error.
  Future<void> call({
    required String challengeId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final challenge = await _challengeRepo.getById(challengeId);
    if (challenge == null) throw ChallengeNotFound(challengeId);

    // Idempotency: already settled.
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

      final entry = LedgerEntryEntity(
        id: uuidGenerator(),
        userId: pr.userId,
        deltaCoins: pr.coinsEarned,
        reason: reason,
        refId: challengeId,
        createdAtMs: nowMs,
      );
      await _ledgerRepo.append(entry);

      final wallet = await _walletRepo.getByUserId(pr.userId);
      await _walletRepo.save(wallet.copyWith(
        balanceCoins: wallet.balanceCoins + pr.coinsEarned,
        lifetimeEarnedCoins:
            wallet.lifetimeEarnedCoins + pr.coinsEarned,
      ));
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
        (ChallengeType.teamVsTeam, ParticipantOutcome.won) =>
          LedgerReason.challengeTeamWon,
        (ChallengeType.teamVsTeam, ParticipantOutcome.tied) =>
          LedgerReason.challengeTeamCompleted,
        (ChallengeType.teamVsTeam, _) =>
          LedgerReason.challengeTeamCompleted,
        (ChallengeType.group, _) =>
          LedgerReason.challengeGroupCompleted,
      };
}
