import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Drift implementation of [IWalletRepo].
final class DriftWalletRepo implements IWalletRepo {
  final AppDatabase _db;

  const DriftWalletRepo(this._db);

  @override
  Future<WalletEntity> getByUserId(String userId) async {
    final query = _db.select(_db.wallets)
      ..where((t) => t.userId.equals(userId));
    final row = await query.getSingleOrNull();

    if (row != null) return _toEntity(row);

    final fresh = WalletEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(WalletEntity wallet) async {
    await _db.into(_db.wallets).insertOnConflictUpdate(
          _toCompanion(wallet),
        );
  }

  // ── Mappers ──

  static WalletsCompanion _toCompanion(WalletEntity e) {
    return WalletsCompanion.insert(
      userId: e.userId,
      balanceCoins: e.balanceCoins,
      pendingCoins: Value(e.pendingCoins),
      lifetimeEarnedCoins: e.lifetimeEarnedCoins,
      lifetimeSpentCoins: e.lifetimeSpentCoins,
      lastReconciledAtMs: Value(e.lastReconciledAtMs),
    );
  }

  static WalletEntity _toEntity(Wallet r) {
    return WalletEntity(
      userId: r.userId,
      balanceCoins: r.balanceCoins,
      pendingCoins: r.pendingCoins,
      lifetimeEarnedCoins: r.lifetimeEarnedCoins,
      lifetimeSpentCoins: r.lifetimeSpentCoins,
      lastReconciledAtMs: r.lastReconciledAtMs,
    );
  }
}
