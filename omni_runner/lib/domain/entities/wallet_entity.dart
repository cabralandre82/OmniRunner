import 'package:equatable/equatable.dart';

/// A user's OmniCoins wallet.
///
/// Holds the current balance, which is always the sum of all
/// [LedgerEntryEntity.deltaCoins] for this user. The wallet itself
/// stores no transaction history — that lives in the ledger.
///
/// Immutable value object. No logic. No behavior.
/// See `docs/GAMIFICATION_POLICY.md` §2 for Coin rules.
final class WalletEntity extends Equatable {
  /// Owner user ID.
  final String userId;

  /// Available balance in OmniCoins. Always ≥ 0.
  /// These Coins can be used for challenges, cosmetics, etc.
  final int balanceCoins;

  /// Coins awaiting clearing between assessorias. Always ≥ 0.
  /// Released to [balanceCoins] after both groups confirm the clearing.
  final int pendingCoins;

  /// Total Coins earned (lifetime, credits only).
  final int lifetimeEarnedCoins;

  /// Total Coins spent (lifetime, debits only, stored as positive).
  final int lifetimeSpentCoins;

  /// Last time the balance was reconciled against the ledger (ms epoch UTC).
  /// Null if never reconciled.
  final int? lastReconciledAtMs;

  const WalletEntity({
    required this.userId,
    this.balanceCoins = 0,
    this.pendingCoins = 0,
    this.lifetimeEarnedCoins = 0,
    this.lifetimeSpentCoins = 0,
    this.lastReconciledAtMs,
  });

  /// Available + pending combined.
  int get totalCoins => balanceCoins + pendingCoins;

  /// Whether pending Coins exist (cross-assessoria clearing in progress).
  bool get hasPending => pendingCoins > 0;

  /// Whether the user can afford a purchase of [cost] Coins.
  /// Only [balanceCoins] (available) count — pending cannot be spent.
  bool canAfford(int cost) => balanceCoins >= cost;

  WalletEntity copyWith({
    int? balanceCoins,
    int? pendingCoins,
    int? lifetimeEarnedCoins,
    int? lifetimeSpentCoins,
    int? lastReconciledAtMs,
  }) =>
      WalletEntity(
        userId: userId,
        balanceCoins: balanceCoins ?? this.balanceCoins,
        pendingCoins: pendingCoins ?? this.pendingCoins,
        lifetimeEarnedCoins:
            lifetimeEarnedCoins ?? this.lifetimeEarnedCoins,
        lifetimeSpentCoins:
            lifetimeSpentCoins ?? this.lifetimeSpentCoins,
        lastReconciledAtMs:
            lastReconciledAtMs ?? this.lastReconciledAtMs,
      );

  @override
  List<Object?> get props => [
        userId,
        balanceCoins,
        pendingCoins,
        lifetimeEarnedCoins,
        lifetimeSpentCoins,
        lastReconciledAtMs,
      ];
}
