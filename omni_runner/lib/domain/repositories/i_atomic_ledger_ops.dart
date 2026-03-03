import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';

/// Atomically appends a ledger entry and saves the wallet in a single
/// transaction. Prevents drift between the two if the app crashes mid-write.
///
/// Domain interface — implementation in data layer wraps both operations
/// in one Isar `writeTxn()` (or equivalent DB transaction).
abstract interface class IAtomicLedgerOps {
  Future<void> appendEntryAndSaveWallet(
    LedgerEntryEntity entry,
    WalletEntity wallet,
  );
}
