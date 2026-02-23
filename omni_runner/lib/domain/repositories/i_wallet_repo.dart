import 'package:omni_runner/domain/entities/wallet_entity.dart';

/// Contract for persisting and retrieving user wallets.
///
/// Domain interface. Implementation lives in data layer.
/// Dependency direction: data → domain (implements this).
abstract interface class IWalletRepo {
  /// Get the wallet for a user. Creates a zero-balance wallet if none exists.
  Future<WalletEntity> getByUserId(String userId);

  Future<void> save(WalletEntity wallet);
}
