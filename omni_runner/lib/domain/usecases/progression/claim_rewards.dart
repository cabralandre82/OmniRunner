import 'dart:math' as math;

import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';

/// Summary of all rewards claimed in a single post-session pass.
final class ClaimResult {
  final int totalXpCredited;
  final int totalCoinsCredited;

  /// XP forfeited due to daily bonus cap (500/day for non-session sources).
  final int xpCapped;

  /// Breakdown per source.
  final List<ClaimEntry> entries;

  const ClaimResult({
    this.totalXpCredited = 0,
    this.totalCoinsCredited = 0,
    this.xpCapped = 0,
    this.entries = const [],
  });
}

/// One line-item of the claim receipt.
final class ClaimEntry {
  final XpSource source;
  final String refId;
  final int xp;
  final int coins;

  const ClaimEntry({
    required this.source,
    required this.refId,
    this.xp = 0,
    this.coins = 0,
  });
}

/// Credits XP and OmniCoins for badges unlocked and missions completed.
///
/// Enforces the daily non-session XP cap (500/day, PROGRESSION_SPEC §4).
/// Idempotent per (refId, source) — will not double-credit.
///
/// This use case is the single entry point for crediting non-session
/// rewards, ensuring consistent cap enforcement and audit trail.
final class ClaimRewards {
  final IXpTransactionRepo _xpRepo;
  final IProfileProgressRepo _profileRepo;
  final ILedgerRepo _ledgerRepo;
  final IWalletRepo _walletRepo;

  static const _dailyBonusXpCap = 500;

  const ClaimRewards({
    required IXpTransactionRepo xpRepo,
    required IProfileProgressRepo profileRepo,
    required ILedgerRepo ledgerRepo,
    required IWalletRepo walletRepo,
  })  : _xpRepo = xpRepo,
        _profileRepo = profileRepo,
        _ledgerRepo = ledgerRepo,
        _walletRepo = walletRepo;

  /// Claims rewards for newly unlocked [badges] and completed [missions].
  ///
  /// [missionDefs] maps mission IDs to their definitions (for reward values).
  Future<ClaimResult> call({
    required String userId,
    required List<BadgeAwardEntity> badges,
    required List<MissionProgressEntity> missions,
    required Map<String, MissionEntity> missionDefs,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final entries = <ClaimEntry>[];
    var totalXp = 0;
    var totalCoins = 0;
    var totalCapped = 0;

    final bonusXpToday = await _xpRepo.sumBonusXpToday(userId);
    var remainingBonusXp = math.max(0, _dailyBonusXpCap - bonusXpToday);

    // ── Badges ──
    for (final badge in badges) {
      final existing = await _xpRepo.getByRefId(badge.badgeId);
      if (existing.any((tx) =>
          tx.source == XpSource.badge && tx.userId == userId)) {
        continue;
      }

      final rawXp = badge.xpAwarded;
      final effectiveXp = math.min(rawXp, remainingBonusXp);
      final capped = rawXp - effectiveXp;
      totalCapped += capped;

      if (effectiveXp > 0) {
        await _xpRepo.append(XpTransactionEntity(
          id: uuidGenerator(),
          userId: userId,
          xp: effectiveXp,
          source: XpSource.badge,
          refId: badge.badgeId,
          createdAtMs: nowMs,
        ));
        totalXp += effectiveXp;
        remainingBonusXp -= effectiveXp;
      }

      if (badge.coinsAwarded > 0) {
        await _creditCoins(
          userId: userId,
          coins: badge.coinsAwarded,
          reason: LedgerReason.badgeReward,
          refId: badge.badgeId,
          uuidGenerator: uuidGenerator,
          nowMs: nowMs,
        );
        totalCoins += badge.coinsAwarded;
      }

      entries.add(ClaimEntry(
        source: XpSource.badge,
        refId: badge.badgeId,
        xp: effectiveXp,
        coins: badge.coinsAwarded,
      ));
    }

    // ── Missions ──
    for (final mission in missions) {
      final def = missionDefs[mission.missionId];
      if (def == null) continue;

      final existing = await _xpRepo.getByRefId(mission.missionId);
      if (existing.any((tx) =>
          tx.source == XpSource.mission && tx.userId == userId)) {
        continue;
      }

      final rawXp = def.xpReward;
      final effectiveXp = math.min(rawXp, remainingBonusXp);
      final capped = rawXp - effectiveXp;
      totalCapped += capped;

      if (effectiveXp > 0) {
        await _xpRepo.append(XpTransactionEntity(
          id: uuidGenerator(),
          userId: userId,
          xp: effectiveXp,
          source: XpSource.mission,
          refId: mission.missionId,
          createdAtMs: nowMs,
        ));
        totalXp += effectiveXp;
        remainingBonusXp -= effectiveXp;
      }

      if (def.coinsReward > 0) {
        await _creditCoins(
          userId: userId,
          coins: def.coinsReward,
          reason: LedgerReason.missionReward,
          refId: mission.missionId,
          uuidGenerator: uuidGenerator,
          nowMs: nowMs,
        );
        totalCoins += def.coinsReward;
      }

      entries.add(ClaimEntry(
        source: XpSource.mission,
        refId: mission.missionId,
        xp: effectiveXp,
        coins: def.coinsReward,
      ));
    }

    // ── Update profile ──
    if (totalXp > 0) {
      final profile = await _profileRepo.getByUserId(userId);
      await _profileRepo.save(profile.copyWith(
        totalXp: profile.totalXp + totalXp,
        seasonXp: profile.seasonXp + totalXp,
      ));
    }

    return ClaimResult(
      totalXpCredited: totalXp,
      totalCoinsCredited: totalCoins,
      xpCapped: totalCapped,
      entries: entries,
    );
  }

  Future<void> _creditCoins({
    required String userId,
    required int coins,
    required LedgerReason reason,
    required String refId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final existing = await _ledgerRepo.getByRefId(refId);
    if (existing.any((e) => e.userId == userId && e.reason == reason)) {
      return;
    }

    await _ledgerRepo.append(LedgerEntryEntity(
      id: uuidGenerator(),
      userId: userId,
      deltaCoins: coins,
      reason: reason,
      refId: refId,
      createdAtMs: nowMs,
    ));

    final wallet = await _walletRepo.getByUserId(userId);
    await _walletRepo.save(wallet.copyWith(
      balanceCoins: wallet.balanceCoins + coins,
      lifetimeEarnedCoins: wallet.lifetimeEarnedCoins + coins,
    ));
  }
}
