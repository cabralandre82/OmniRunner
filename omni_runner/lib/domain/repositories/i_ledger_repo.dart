import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';

/// Contract for the append-only Coins ledger.
///
/// Domain interface. Implementation lives in data layer.
/// Entries are never updated or deleted — only appended.
/// See `docs/GAMIFICATION_POLICY.md` §8.3 for audit rules.
///
/// Dependency direction: data → domain (implements this).
abstract interface class ILedgerRepo {
  /// Append a new entry. Throws if [entry.id] already exists (dedup).
  Future<void> append(LedgerEntryEntity entry);

  /// All entries for a user, ordered by [createdAtMs] descending.
  Future<List<LedgerEntryEntity>> getByUserId(String userId);

  /// Entries linked to a specific reference (session/challenge).
  Future<List<LedgerEntryEntity>> getByRefId(String refId);

  /// Number of credit entries for [userId] created today (UTC).
  /// Used for daily rate limiting (max 10 sessions/day).
  Future<int> countCreditsToday(String userId);

  /// Sum of all [deltaCoins] for a user. Used for reconciliation.
  Future<int> sumByUserId(String userId);
}
