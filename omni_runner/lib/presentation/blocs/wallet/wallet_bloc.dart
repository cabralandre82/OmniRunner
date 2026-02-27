import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_state.dart';

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final IWalletRepo _walletRepo;
  final ILedgerRepo _ledgerRepo;

  String _userId = '';

  WalletBloc({
    required IWalletRepo walletRepo,
    required ILedgerRepo ledgerRepo,
  })  : _walletRepo = walletRepo,
        _ledgerRepo = ledgerRepo,
        super(const WalletInitial()) {
    on<LoadWallet>(_onLoad);
    on<RefreshWallet>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadWallet event,
    Emitter<WalletState> emit,
  ) async {
    _userId = event.userId;
    emit(const WalletLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshWallet event,
    Emitter<WalletState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<WalletState> emit) async {
    try {
      await _syncFromServer();
      final wallet = await _walletRepo.getByUserId(_userId);
      final history = await _ledgerRepo.getByUserId(_userId);
      emit(WalletLoaded(wallet: wallet, history: history));
    } on Exception catch (e) {
      emit(WalletError('Erro ao carregar OmniCoins: $e'));
    }
  }

  /// Pulls the authoritative wallet balance from Supabase and persists to Isar.
  Future<void> _syncFromServer() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('wallets')
          .select('balance_coins, lifetime_earned_coins, lifetime_spent_coins')
          .eq('user_id', _userId)
          .maybeSingle();
      if (row == null) return;
      final remote = WalletEntity(
        userId: _userId,
        balanceCoins: (row['balance_coins'] as num?)?.toInt() ?? 0,
        lifetimeEarnedCoins: (row['lifetime_earned_coins'] as num?)?.toInt() ?? 0,
        lifetimeSpentCoins: (row['lifetime_spent_coins'] as num?)?.toInt() ?? 0,
      );
      await _walletRepo.save(remote);
    } on Exception {
      // Offline or error — fall back to local Isar data
    }
  }
}
