import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_atomic_ledger_ops.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Result of a ledger operation.
final class LedgerOpResult {
  final bool success;
  final GamificationFailure? failure;

  /// How many entries were actually written (0 if idempotent skip).
  final int entriesWritten;

  const LedgerOpResult._({
    required this.success,
    this.failure,
    this.entriesWritten = 0,
  });

  const LedgerOpResult.ok(int written)
      : this._(success: true, entriesWritten: written);

  const LedgerOpResult.skipped()
      : this._(success: true, entriesWritten: 0);

  const LedgerOpResult.failed(GamificationFailure reason)
      : this._(success: false, failure: reason);
}

/// Domain service for all Coin movements in the gamification engine.
///
/// Centralises the 4 invariants:
///   1. **Debit entry fee** — each participant pays when a challenge starts.
///   2. **Transfer pool to winner** — winner receives sum of all entry fees.
///   3. **Never negative balance** — any debit that would cause balance < 0
///      is rejected with [InsufficientBalance].
///   4. **Idempotency** — every operation checks the ledger for an existing
///      entry with the same `refId` + `reason` combo before writing.
///
/// All methods return [LedgerOpResult] instead of throwing, so callers
/// can decide how to surface failures. The only exception is
/// [InsufficientBalance] during multi-participant debit, which is returned
/// per-user so the caller can decide on partial rollback.
///
/// Stateless — depends only on repos.
final class LedgerService {
  final ILedgerRepo _ledgerRepo;
  final IWalletRepo _walletRepo;
  final IAtomicLedgerOps? _atomicOps;

  const LedgerService({
    required ILedgerRepo ledgerRepo,
    required IWalletRepo walletRepo,
    IAtomicLedgerOps? atomicOps,
  })  : _ledgerRepo = ledgerRepo,
        _walletRepo = walletRepo,
        _atomicOps = atomicOps;

  // ── 1. DEBIT ENTRY FEES ─────────────────────────────────────

  /// Debits [challenge.rules.entryFeeCoins] from every accepted participant.
  ///
  /// Skips participants who already have a `challengeEntryFee` entry for
  /// this challenge (idempotency). Returns [InsufficientBalance] for any
  /// participant whose wallet cannot cover the fee — that participant is
  /// NOT debited, but all others who can afford it ARE.
  ///
  /// Returns one [LedgerOpResult] summarising the entire operation.
  /// If any participant was skipped due to insufficient balance, the
  /// result's [failure] is set to the first [InsufficientBalance].
  Future<LedgerOpResult> debitEntryFees({
    required ChallengeEntity challenge,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final fee = challenge.rules.entryFeeCoins;
    if (fee <= 0) return const LedgerOpResult.skipped();

    final accepted = challenge.participants
        .where((p) => p.status == ParticipantStatus.accepted)
        .toList();

    var written = 0;
    GamificationFailure? firstFailure;

    for (final p in accepted) {
      final result = await _debitSingle(
        userId: p.userId,
        amount: fee,
        reason: LedgerReason.challengeEntryFee,
        refId: challenge.id,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );

      if (result.success) {
        written += result.entriesWritten;
      } else {
        firstFailure ??= result.failure;
      }
    }

    if (firstFailure != null) {
      return LedgerOpResult.failed(firstFailure);
    }
    return LedgerOpResult.ok(written);
  }

  // ── 2. TRANSFER POOL TO WINNER ──────────────────────────────

  /// Credits the total pool (entry fee × accepted count) to the winner(s).
  ///
  /// If there are multiple winners (tie), the pool is split equally.
  /// Remainder coins (from integer division) go to the first winner.
  ///
  /// Idempotent — skips winners who already have a `challengePoolWon`
  /// entry for this challenge.
  Future<LedgerOpResult> transferPoolToWinners({
    required ChallengeEntity challenge,
    required ChallengeResultEntity result,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final fee = challenge.rules.entryFeeCoins;
    if (fee <= 0) return const LedgerOpResult.skipped();

    final acceptedCount = challenge.participants
        .where((p) => p.status == ParticipantStatus.accepted)
        .length;
    final totalPool = fee * acceptedCount;
    if (totalPool <= 0) return const LedgerOpResult.skipped();

    final winners = result.winners;
    if (winners.isEmpty) return const LedgerOpResult.skipped();

    final sharePerWinner = totalPool ~/ winners.length;
    final remainder = totalPool % winners.length;
    var written = 0;

    for (var i = 0; i < winners.length; i++) {
      final share = sharePerWinner + (i == 0 ? remainder : 0);
      if (share <= 0) continue;

      final opResult = await _creditSingle(
        userId: winners[i].userId,
        amount: share,
        reason: LedgerReason.challengePoolWon,
        refId: challenge.id,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );
      written += opResult.entriesWritten;
    }

    return LedgerOpResult.ok(written);
  }

  // ── 3. REFUND ENTRY FEES ────────────────────────────────────

  /// Refunds entry fees to all participants who were debited.
  ///
  /// Used when a challenge is cancelled. Only refunds users who have
  /// an existing `challengeEntryFee` entry (debit) for this challenge
  /// and do NOT yet have a `challengeEntryRefund` entry (idempotency).
  Future<LedgerOpResult> refundEntryFees({
    required ChallengeEntity challenge,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final fee = challenge.rules.entryFeeCoins;
    if (fee <= 0) return const LedgerOpResult.skipped();

    final existing = await _ledgerRepo.getByRefId(challenge.id);

    final debited = existing
        .where((e) => e.reason == LedgerReason.challengeEntryFee)
        .map((e) => e.userId)
        .toSet();

    final alreadyRefunded = existing
        .where((e) => e.reason == LedgerReason.challengeEntryRefund)
        .map((e) => e.userId)
        .toSet();

    var written = 0;

    for (final userId in debited) {
      if (alreadyRefunded.contains(userId)) continue;

      final opResult = await _creditSingle(
        userId: userId,
        amount: fee,
        reason: LedgerReason.challengeEntryRefund,
        refId: challenge.id,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );
      written += opResult.entriesWritten;
    }

    return LedgerOpResult.ok(written);
  }

  // ── 4. CREDIT REWARD (generic) ─────────────────────────────

  /// Credits [amount] to a user's wallet with the given [reason].
  ///
  /// Idempotent — skips if an entry with the same `(userId, refId, reason)`
  /// already exists in the ledger.
  ///
  /// Used by [SettleChallenge] to write winner/participation rewards
  /// through a single, consistent credit path.
  Future<LedgerOpResult> creditReward({
    required String userId,
    required int amount,
    required LedgerReason reason,
    required String refId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    if (amount <= 0) return const LedgerOpResult.skipped();
    return _creditSingle(
      userId: userId,
      amount: amount,
      reason: reason,
      refId: refId,
      uuidGenerator: uuidGenerator,
      nowMs: nowMs,
    );
  }

  // ── INTERNAL: SINGLE-USER DEBIT ─────────────────────────────

  /// Debits [amount] from a user's wallet.
  ///
  /// Returns [InsufficientBalance] if balance < amount.
  /// Returns [LedgerOpResult.skipped()] if an entry with the same
  /// [refId] + [reason] already exists for this user (idempotency).
  Future<LedgerOpResult> _debitSingle({
    required String userId,
    required int amount,
    required LedgerReason reason,
    required String refId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    if (await _alreadyExists(userId, refId, reason)) {
      return const LedgerOpResult.skipped();
    }

    final wallet = await _walletRepo.getByUserId(userId);
    if (wallet.balanceCoins < amount) {
      return LedgerOpResult.failed(
        InsufficientBalance(wallet.balanceCoins, amount),
      );
    }

    final entry = LedgerEntryEntity(
      id: uuidGenerator(),
      userId: userId,
      deltaCoins: -amount,
      reason: reason,
      refId: refId,
      createdAtMs: nowMs,
    );
    final updatedWallet = wallet.copyWith(
      balanceCoins: wallet.balanceCoins - amount,
      lifetimeSpentCoins: wallet.lifetimeSpentCoins + amount,
    );

    await _persistAtomically(entry, updatedWallet);
    return const LedgerOpResult.ok(1);
  }

  // ── INTERNAL: SINGLE-USER CREDIT ────────────────────────────

  Future<LedgerOpResult> _creditSingle({
    required String userId,
    required int amount,
    required LedgerReason reason,
    required String refId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    if (await _alreadyExists(userId, refId, reason)) {
      return const LedgerOpResult.skipped();
    }

    final entry = LedgerEntryEntity(
      id: uuidGenerator(),
      userId: userId,
      deltaCoins: amount,
      reason: reason,
      refId: refId,
      createdAtMs: nowMs,
    );
    final wallet = await _walletRepo.getByUserId(userId);
    final updatedWallet = wallet.copyWith(
      balanceCoins: wallet.balanceCoins + amount,
      lifetimeEarnedCoins: wallet.lifetimeEarnedCoins + amount,
    );

    await _persistAtomically(entry, updatedWallet);
    return const LedgerOpResult.ok(1);
  }

  // ── INTERNAL: ATOMIC PERSISTENCE ────────────────────────────

  /// Writes ledger entry + wallet in one transaction when [_atomicOps]
  /// is available; falls back to sequential writes otherwise.
  Future<void> _persistAtomically(
    LedgerEntryEntity entry,
    WalletEntity wallet,
  ) async {
    if (_atomicOps != null) {
      await _atomicOps.appendEntryAndSaveWallet(entry, wallet);
    } else {
      await _ledgerRepo.append(entry);
      await _walletRepo.save(wallet);
    }
  }

  // ── INTERNAL: IDEMPOTENCY CHECK ─────────────────────────────

  /// Returns true if a ledger entry already exists for this user +
  /// refId + reason combination.
  Future<bool> _alreadyExists(
    String userId,
    String refId,
    LedgerReason reason,
  ) async {
    final entries = await _ledgerRepo.getByRefId(refId);
    return entries.any((e) => e.userId == userId && e.reason == reason);
  }
}
