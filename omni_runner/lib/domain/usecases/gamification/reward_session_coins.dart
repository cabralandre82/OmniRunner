import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
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

/// Awards OmniCoins for a completed, verified workout session.
///
/// Validates per GAMIFICATION_POLICY.md §3 / §8:
/// - Session status is [WorkoutStatus.completed].
/// - Session is verified (`isVerified == true`).
/// - Session distance ≥ 1 km (configurable via [minDistanceM]).
/// - Daily limit not exceeded (max [maxSessionsPerDay]).
/// - Session not already rewarded (dedup via ledger refId).
///
/// Awards [coinsPerSession] (default 10) on success.
/// Returns [RewardResult] instead of throwing — caller decides
/// whether to surface the failure to the user.
///
/// Conforms to [O4]: single `call()` method.
final class RewardSessionCoins {
  final ILedgerRepo _ledgerRepo;
  final IWalletRepo _walletRepo;

  static const _defaultCoins = 10;
  static const _defaultMinDistanceM = 1000.0;
  static const _defaultMaxSessionsPerDay = 10;

  const RewardSessionCoins({
    required ILedgerRepo ledgerRepo,
    required IWalletRepo walletRepo,
  })  : _ledgerRepo = ledgerRepo,
        _walletRepo = walletRepo;

  /// [session] is the completed workout.
  /// [uuidGenerator] provides a unique ID for the ledger entry.
  /// [nowMs] is the current timestamp.
  Future<RewardResult> call({
    required WorkoutSessionEntity session,
    required String Function() uuidGenerator,
    required int nowMs,
    int coinsPerSession = _defaultCoins,
    double minDistanceM = _defaultMinDistanceM,
    int maxSessionsPerDay = _defaultMaxSessionsPerDay,
  }) async {
    if (session.status != WorkoutStatus.completed) {
      return RewardResult.rejected(
        SessionNotCompleted(session.id, session.status.name),
      );
    }

    if (!session.isVerified) {
      return RewardResult.rejected(UnverifiedSession(session.id));
    }

    final distanceM = session.totalDistanceM ?? 0.0;
    if (distanceM < minDistanceM) {
      return RewardResult.rejected(
        SessionBelowMinimum(session.id, minDistanceM, distanceM),
      );
    }

    final userId = session.userId;
    if (userId == null || userId.isEmpty) {
      return RewardResult.rejected(SessionNoUser(session.id));
    }

    // Dedup: check if this session was already rewarded.
    final existing = await _ledgerRepo.getByRefId(session.id);
    if (existing.any((e) => e.reason == LedgerReason.sessionCompleted)) {
      return RewardResult.rejected(
        SessionAlreadySubmitted(session.id, 'session_reward'),
      );
    }

    // Rate limit: max N rewarded sessions per UTC day.
    final todayCount = await _ledgerRepo.countCreditsToday(userId);
    if (todayCount >= maxSessionsPerDay) {
      return RewardResult.rejected(DailyLimitReached(todayCount));
    }

    // All checks passed — credit Coins.
    final entry = LedgerEntryEntity(
      id: uuidGenerator(),
      userId: userId,
      deltaCoins: coinsPerSession,
      reason: LedgerReason.sessionCompleted,
      refId: session.id,
      createdAtMs: nowMs,
    );
    await _ledgerRepo.append(entry);

    final wallet = await _walletRepo.getByUserId(userId);
    await _walletRepo.save(wallet.copyWith(
      balanceCoins: wallet.balanceCoins + coinsPerSession,
      lifetimeEarnedCoins: wallet.lifetimeEarnedCoins + coinsPerSession,
    ));

    return RewardResult.success(coinsPerSession);
  }
}
