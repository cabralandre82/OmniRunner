// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'wallet_record.g.dart';

/// Isar collection for persisting user wallets.
///
/// One record per user. Maps to/from [WalletEntity] in the domain layer.
/// Balance is a denormalized cache — reconciled against the ledger
/// periodically via [GetWallet].
@collection
class WalletRecord {
  Id isarId = Isar.autoIncrement;

  /// Owner user ID. Unique — one wallet per user.
  @Index(unique: true)
  late String userId;

  /// Current available balance in OmniCoins.
  late int balanceCoins;

  /// Coins awaiting cross-assessoria clearing.
  int pendingCoins = 0;

  /// Total lifetime Coins earned (credits only).
  late int lifetimeEarnedCoins;

  /// Total lifetime Coins spent (debits only, stored as positive).
  late int lifetimeSpentCoins;

  /// Last reconciliation timestamp (ms epoch UTC). Null if never.
  int? lastReconciledAtMs;
}
