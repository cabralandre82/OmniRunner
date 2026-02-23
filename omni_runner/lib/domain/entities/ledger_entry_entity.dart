import 'package:equatable/equatable.dart';

/// Why Coins were credited or debited.
///
/// Each reason maps to a rule in `docs/GAMIFICATION_POLICY.md` §3 / §4.
enum LedgerReason {
  /// Completed a verified session ≥1 km (+10 Coins).
  sessionCompleted,

  /// Completed a 1v1 challenge (+25 Coins).
  challengeOneVsOneCompleted,

  /// Won a 1v1 challenge (+15 bonus Coins).
  challengeOneVsOneWon,

  /// Completed a group challenge (+30 Coins).
  challengeGroupCompleted,

  /// Weekly streak: 3+ verified runs in a week (+20 Coins).
  streakWeekly,

  /// Monthly streak: 12+ verified runs in a month (+50 Coins).
  streakMonthly,

  /// New personal record — distance (+30 Coins).
  prDistance,

  /// New personal record — pace (+30 Coins).
  prPace,

  /// Entry fee debited from participant when challenge starts (negative delta).
  challengeEntryFee,

  /// Pool of entry fees credited to the winner on settlement (positive delta).
  challengePoolWon,

  /// Entry fee refunded on challenge cancellation (positive delta).
  challengeEntryRefund,

  /// Spent Coins on a cosmetic item (negative delta).
  cosmeticPurchase,

  /// Manual adjustment by admin / system correction (positive or negative).
  adminAdjustment,

  /// Badge unlocked — OmniCoins reward (+N Coins).
  badgeReward,

  /// Mission completed — OmniCoins reward (+N Coins).
  missionReward,

  /// Cross-assessoria reward held pending clearing (positive delta to pending).
  crossAssessoriaPending,

  /// Pending coins released after clearing confirmation (moves from pending to available).
  crossAssessoriaCleared,

  /// Pending coins burned on assessoria switch before clearing.
  crossAssessoriaBurned,

  /// Completed a team-vs-team challenge (+30 Coins).
  challengeTeamCompleted,

  /// Won a team-vs-team challenge (+15 bonus Coins).
  challengeTeamWon,
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
