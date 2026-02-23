import 'package:omni_runner/domain/entities/profile_progress_entity.dart';

/// Contract for the append-only XP transaction log.
///
/// Mirrors the [ILedgerRepo] pattern but for XP instead of Coins.
/// Entries are never updated or deleted — only appended.
/// See `docs/PROGRESSION_SPEC.md` §4.
abstract interface class IXpTransactionRepo {
  Future<void> append(XpTransactionEntity tx);

  /// All XP transactions for a user, ordered by [createdAtMs] descending.
  Future<List<XpTransactionEntity>> getByUserId(String userId);

  /// Entries linked to a specific reference (session/badge/mission).
  Future<List<XpTransactionEntity>> getByRefId(String refId);

  /// Sum of XP from [XpSource.session] entries created today (UTC).
  Future<int> sumSessionXpToday(String userId);

  /// Sum of XP from non-session sources created today (UTC).
  Future<int> sumBonusXpToday(String userId);

  /// Total lifetime XP for a user.
  Future<int> sumByUserId(String userId);

  /// Total XP earned within a date range (for season XP calculation).
  Future<int> sumByUserIdInRange(String userId, int fromMs, int toMs);
}
