import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_wallet_remote_source.dart';

class SupabaseWalletRemoteSource implements IWalletRemoteSource {
  @override
  Future<WalletEntity?> fetchWallet(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('wallets')
          .select('balance_coins, lifetime_earned_coins, lifetime_spent_coins')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return WalletEntity(
        userId: userId,
        balanceCoins: (row['balance_coins'] as num?)?.toInt() ?? 0,
        lifetimeEarnedCoins:
            (row['lifetime_earned_coins'] as num?)?.toInt() ?? 0,
        lifetimeSpentCoins:
            (row['lifetime_spent_coins'] as num?)?.toInt() ?? 0,
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<LedgerEntryEntity>> fetchLedger(String userId) async {
    if (!AppConfig.isSupabaseReady || userId.isEmpty) return const [];
    try {
      final rows = await Supabase.instance.client
          .from('coin_ledger')
          .select('id, user_id, delta_coins, reason, ref_id, created_at_ms')
          .eq('user_id', userId)
          .order('created_at_ms', ascending: false)
          .limit(200);

      final entries = <LedgerEntryEntity>[];
      for (final r in rows) {
        final reason =
            LedgerReason.fromSnakeCase(r['reason'] as String? ?? '');
        if (reason == null) continue;
        entries.add(LedgerEntryEntity(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          deltaCoins: (r['delta_coins'] as num).toInt(),
          reason: reason,
          refId: r['ref_id'] as String? ?? '',
          issuerGroupId: null,
          createdAtMs: (r['created_at_ms'] as num).toInt(),
        ));
      }
      return entries;
    } on Exception {
      return const [];
    }
  }
}
