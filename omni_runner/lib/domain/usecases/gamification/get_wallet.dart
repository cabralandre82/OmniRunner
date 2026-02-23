import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

/// Retrieves the user's wallet, optionally reconciling balance with the
/// ledger if the cached balance is stale.
///
/// Reconciliation compares `wallet.balanceCoins` against `sum(ledger)`.
/// If they differ, the wallet is corrected and persisted.
///
/// Conforms to [O4]: single `call()` method.
final class GetWallet {
  final IWalletRepo _walletRepo;
  final ILedgerRepo _ledgerRepo;

  const GetWallet({
    required IWalletRepo walletRepo,
    required ILedgerRepo ledgerRepo,
  })  : _walletRepo = walletRepo,
        _ledgerRepo = ledgerRepo;

  /// If [reconcile] is true, verifies balance against ledger sum.
  /// Returns the (possibly corrected) wallet.
  Future<WalletEntity> call({
    required String userId,
    bool reconcile = false,
  }) async {
    final wallet = await _walletRepo.getByUserId(userId);

    if (!reconcile) return wallet;

    final ledgerSum = await _ledgerRepo.sumByUserId(userId);
    if (ledgerSum == wallet.balanceCoins) return wallet;

    final corrected = wallet.copyWith(
      balanceCoins: ledgerSum,
      lastReconciledAtMs:
          DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await _walletRepo.save(corrected);
    return corrected;
  }
}
