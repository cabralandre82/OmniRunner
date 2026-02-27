import 'package:equatable/equatable.dart';

/// Why Coins were credited or debited.
///
/// Each reason maps to a rule in `docs/GAMIFICATION_POLICY.md` §3 / §4.
enum LedgerReason {
  /// DEPRECATED — sessions do not award coins. Kept for legacy ledger entries.
  sessionCompleted,

  /// DEPRECATED — free challenges award zero coins. Kept for legacy.
  challengeOneVsOneCompleted,

  /// Won a staked 1v1 challenge — receives the entry-fee pool.
  challengeOneVsOneWon,

  /// DEPRECATED — free group challenges award zero coins. Kept for legacy.
  challengeGroupCompleted,

  /// DEPRECATED — streaks do not award coins. Kept for legacy.
  streakWeekly,

  /// DEPRECATED — streaks do not award coins. Kept for legacy.
  streakMonthly,

  /// DEPRECATED — PRs do not award coins. Kept for legacy.
  prDistance,

  /// DEPRECATED — PRs do not award coins. Kept for legacy.
  prPace,

  /// Entry fee debited from participant when challenge starts (negative delta).
  challengeEntryFee,

  /// Pool of entry fees credited to the winner on settlement (positive delta).
  challengePoolWon,

  /// Entry fee refunded on challenge cancellation (positive delta).
  challengeEntryRefund,

  /// Spent Coins on a cosmetic item (negative delta).
  cosmeticPurchase,

  /// Manual adjustment by admin / assessoria distribution (positive or negative).
  adminAdjustment,

  /// DEPRECATED — badges do not award coins. Kept for legacy.
  badgeReward,

  /// DEPRECATED — missions do not award coins. Kept for legacy.
  missionReward,

  /// Cross-assessoria reward held pending clearing (positive delta to pending).
  crossAssessoriaPending,

  /// Pending coins released after clearing confirmation (moves from pending to available).
  crossAssessoriaCleared,

  /// Pending coins burned on assessoria switch before clearing.
  crossAssessoriaBurned,

  /// Won a staked team-vs-team challenge — receives share of entry-fee pool.
  challengeTeamCompleted,

  /// Won a staked team-vs-team challenge — receives share of entry-fee pool.
  challengeTeamWon;

  // ── Stable ordinals for Isar persistence ────────────────────────
  // RULE: never change existing values. Only append new entries at the end.
  static const _toInt = <LedgerReason, int>{
    sessionCompleted: 0,
    challengeOneVsOneCompleted: 1,
    challengeOneVsOneWon: 2,
    challengeGroupCompleted: 3,
    streakWeekly: 4,
    streakMonthly: 5,
    prDistance: 6,
    prPace: 7,
    challengeEntryFee: 8,
    challengePoolWon: 9,
    challengeEntryRefund: 10,
    cosmeticPurchase: 11,
    adminAdjustment: 12,
    badgeReward: 13,
    missionReward: 14,
    crossAssessoriaPending: 15,
    crossAssessoriaCleared: 16,
    crossAssessoriaBurned: 17,
    challengeTeamCompleted: 18,
    challengeTeamWon: 19,
  };

  static final _fromInt = <int, LedgerReason>{
    for (final e in _toInt.entries) e.value: e.key,
  };

  /// Fixed integer for Isar storage — immune to enum reordering.
  int get stableOrdinal => _toInt[this]!;

  /// Reverse lookup from a persisted integer.
  static LedgerReason fromStableOrdinal(int ordinal) {
    final reason = _fromInt[ordinal];
    if (reason == null) {
      throw ArgumentError('Unknown LedgerReason ordinal: $ordinal');
    }
    return reason;
  }
}

/// A single, immutable, append-only transaction in the Coins ledger.
///
/// Every Coin gained or spent produces exactly one [LedgerEntryEntity].
/// The current balance is always `sum(deltaCoins)` across all entries
/// for a given [userId].
///
/// Domain-pure — no Flutter or platform imports.
/// See `docs/GAMIFICATION_POLICY.md` §8.3 for audit rules.
final class LedgerEntryEntity extends Equatable {
  /// Unique identifier for this transaction (UUID v4).
  final String id;

  /// Owner of this transaction.
  final String userId;

  /// Signed coin amount: positive = credit, negative = debit.
  final int deltaCoins;

  /// Why this transaction occurred.
  final LedgerReason reason;

  /// Optional reference ID linking to the source entity.
  ///
  /// - [LedgerReason.sessionCompleted] → session ID
  /// - [LedgerReason.challengeOneVsOneCompleted] → challenge ID
  /// - [LedgerReason.cosmeticPurchase] → shop item ID
  /// - [LedgerReason.prDistance] / [LedgerReason.prPace] → session ID
  final String? refId;

  /// When this transaction was recorded (ms since epoch, UTC).
  final int createdAtMs;

  const LedgerEntryEntity({
    required this.id,
    required this.userId,
    required this.deltaCoins,
    required this.reason,
    this.refId,
    required this.createdAtMs,
  });

  /// Whether this entry is a credit (positive Coins).
  bool get isCredit => deltaCoins > 0;

  @override
  List<Object?> get props => [
        id,
        userId,
        deltaCoins,
        reason,
        refId,
        createdAtMs,
      ];
}
