import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Result of attempting to reward Coins for a session.
final class RewardResult {
  final bool rewarded;
  final int coinsAwarded;
  final GamificationFailure? failure;

  const RewardResult._({
    required this.rewarded,
    this.coinsAwarded = 0,
    this.failure,
  });

  const RewardResult.success(int coins)
      : this._(rewarded: true, coinsAwarded: coins);

  const RewardResult.rejected(GamificationFailure reason)
      : this._(rewarded: false, failure: reason);
}

/// DEPRECATED: OmniCoins are only acquired via assessoria.
/// Sessions do NOT award OmniCoins.
///
/// This use case is kept for backward compatibility but always
/// returns [RewardResult.success(0)] — zero coins awarded.
/// Session completion still triggers XP via the progression system.
final class RewardSessionCoins {
  static const _defaultCoins = 10;
  static const _defaultMinDistanceM = 1000.0;
  static const _defaultMaxSessionsPerDay = 10;

  const RewardSessionCoins({
    required ILedgerRepo ledgerRepo,
    required IWalletRepo walletRepo,
  });

  /// OmniCoins are only distributed by assessorias.
  /// Sessions never award coins. Returns success with 0 coins.
  Future<RewardResult> call({
    required WorkoutSessionEntity session,
    required String Function() uuidGenerator,
    required int nowMs,
    int coinsPerSession = _defaultCoins,
    double minDistanceM = _defaultMinDistanceM,
    int maxSessionsPerDay = _defaultMaxSessionsPerDay,
  }) async {
    return const RewardResult.success(0);
  }
}
