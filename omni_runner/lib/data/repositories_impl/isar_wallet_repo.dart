import 'package:isar/isar.dart';

import 'package:omni_runner/core/cache/cache_metadata_store.dart';
import 'package:omni_runner/data/models/isar/wallet_record.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Isar implementation of [IWalletRepo].
final class IsarWalletRepo implements IWalletRepo {
  final Isar _isar;
  final CacheMetadataStore _cacheMeta;

  IsarWalletRepo(this._isar, this._cacheMeta);

  @override
  Future<WalletEntity> getByUserId(String userId) async {
    final record = await _isar.walletRecords
        .where()
        .userIdEqualTo(userId)
        .findFirst();

    if (record != null) return _toEntity(record);

    // Auto-create zero-balance wallet.
    final fresh = WalletEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(WalletEntity wallet) async {
    await _isar.writeTxn(() async {
      // Upsert: find existing by userId or insert new.
      final existing = await _isar.walletRecords
          .where()
          .userIdEqualTo(wallet.userId)
          .findFirst();

      final record = _toRecord(wallet);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.walletRecords.put(record);
    });
    _cacheMeta.recordCacheWriteSync('wallet', wallet.userId);
  }

  // ── Mappers ──

  static WalletRecord _toRecord(WalletEntity e) => WalletRecord()
    ..userId = e.userId
    ..balanceCoins = e.balanceCoins
    ..pendingCoins = e.pendingCoins
    ..lifetimeEarnedCoins = e.lifetimeEarnedCoins
    ..lifetimeSpentCoins = e.lifetimeSpentCoins
    ..lastReconciledAtMs = e.lastReconciledAtMs;

  static WalletEntity _toEntity(WalletRecord r) => WalletEntity(
        userId: r.userId,
        balanceCoins: r.balanceCoins,
        pendingCoins: r.pendingCoins,
        lifetimeEarnedCoins: r.lifetimeEarnedCoins,
        lifetimeSpentCoins: r.lifetimeSpentCoins,
        lastReconciledAtMs: r.lastReconciledAtMs,
      );
}
