// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/ledger_record.dart';
import 'package:omni_runner/data/models/isar/wallet_record.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_atomic_ledger_ops.dart';

/// Isar implementation that wraps ledger append + wallet save in a single
/// `writeTxn()`, guaranteeing all-or-nothing semantics on the client.
final class IsarAtomicLedgerOps implements IAtomicLedgerOps {
  final Isar _isar;

  const IsarAtomicLedgerOps(this._isar);

  @override
  Future<void> appendEntryAndSaveWallet(
    LedgerEntryEntity entry,
    WalletEntity wallet,
  ) async {
    await _isar.writeTxn(() async {
      // 1. Upsert ledger entry (dedup by entryUuid).
      final ledgerRecord = LedgerRecord()
        ..entryUuid = entry.id
        ..userId = entry.userId
        ..deltaCoins = entry.deltaCoins
        ..reasonOrdinal = entry.reason.stableOrdinal
        ..refId = entry.refId
        ..issuerGroupId = entry.issuerGroupId
        ..createdAtMs = entry.createdAtMs;

      final existingLedger = await _isar.ledgerRecords
          .where()
          .entryUuidEqualTo(entry.id)
          .findFirst();
      if (existingLedger != null) ledgerRecord.isarId = existingLedger.isarId;
      await _isar.ledgerRecords.put(ledgerRecord);

      // 2. Upsert wallet.
      final walletRecord = WalletRecord()
        ..userId = wallet.userId
        ..balanceCoins = wallet.balanceCoins
        ..pendingCoins = wallet.pendingCoins
        ..lifetimeEarnedCoins = wallet.lifetimeEarnedCoins
        ..lifetimeSpentCoins = wallet.lifetimeSpentCoins
        ..lastReconciledAtMs = wallet.lastReconciledAtMs;

      final existingWallet = await _isar.walletRecords
          .where()
          .userIdEqualTo(wallet.userId)
          .findFirst();
      if (existingWallet != null) walletRecord.isarId = existingWallet.isarId;
      await _isar.walletRecords.put(walletRecord);
    });
  }
}
