import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_atomic_ledger_ops.dart';

final class DriftAtomicLedgerOps implements IAtomicLedgerOps {
  final AppDatabase _db;

  const DriftAtomicLedgerOps(this._db);

  @override
  Future<void> appendEntryAndSaveWallet(
    LedgerEntryEntity entry,
    WalletEntity wallet,
  ) async {
    await _db.transaction(() async {
      await _db.into(_db.ledgerEntries).insert(
            LedgerEntriesCompanion(
              entryUuid: Value(entry.id),
              userId: Value(entry.userId),
              deltaCoins: Value(entry.deltaCoins),
              reasonOrdinal: Value(entry.reason.name),
              refId: Value(entry.refId),
              issuerGroupId: Value(entry.issuerGroupId),
              createdAtMs: Value(entry.createdAtMs),
            ),
            mode: InsertMode.insertOrReplace,
          );

      await _db.into(_db.wallets).insert(
            WalletsCompanion(
              userId: Value(wallet.userId),
              balanceCoins: Value(wallet.balanceCoins),
              pendingCoins: Value(wallet.pendingCoins),
              lifetimeEarnedCoins: Value(wallet.lifetimeEarnedCoins),
              lifetimeSpentCoins: Value(wallet.lifetimeSpentCoins),
              lastReconciledAtMs: Value(wallet.lastReconciledAtMs),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }
}
