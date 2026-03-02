import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';

/// Remote data source for wallet and ledger data.
///
/// The BLoC calls this to sync server state, then persists to local repos.
/// Implementations may return `null` / empty list when offline.
abstract interface class IWalletRemoteSource {
  /// Fetches the authoritative wallet balance. Returns `null` if unavailable.
  Future<WalletEntity?> fetchWallet(String userId);

  /// Fetches the most recent ledger entries (up to 200).
  Future<List<LedgerEntryEntity>> fetchLedger(String userId);
}
