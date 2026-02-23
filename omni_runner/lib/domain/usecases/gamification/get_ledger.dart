import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';

/// Retrieves the full Coins transaction history for a user.
///
/// Results are ordered by [LedgerEntryEntity.createdAtMs] descending
/// (newest first). Optionally filtered by [LedgerReason].
///
/// Conforms to [O4]: single `call()` method.
final class GetLedger {
  final ILedgerRepo _ledgerRepo;

  const GetLedger({required ILedgerRepo ledgerRepo})
      : _ledgerRepo = ledgerRepo;

  /// [reason] filters entries by a specific reason. Null returns all.
  Future<List<LedgerEntryEntity>> call({
    required String userId,
    LedgerReason? reason,
  }) async {
    final entries = await _ledgerRepo.getByUserId(userId);

    if (reason == null) return entries;

    return entries.where((e) => e.reason == reason).toList();
  }
}
