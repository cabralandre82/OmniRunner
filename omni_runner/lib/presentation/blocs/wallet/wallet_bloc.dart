import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/error_messages.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_state.dart';

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final IWalletRepo _walletRepo;
  final ILedgerRepo _ledgerRepo;
  final IWalletRemoteSource _remote;

  String _userId = '';

  WalletBloc({
    required IWalletRepo walletRepo,
    required ILedgerRepo ledgerRepo,
    required IWalletRemoteSource remote,
  })  : _walletRepo = walletRepo,
        _ledgerRepo = ledgerRepo,
        _remote = remote,
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
      // Sync remote data to local repos (best-effort)
      bool remoteSucceeded = true;
      try {
        final remoteWallet = await _remote.fetchWallet(_userId);
        if (remoteWallet != null) {
          await _walletRepo.save(remoteWallet);
        }

        final remoteLedger = await _remote.fetchLedger(_userId);
        for (final entry in remoteLedger) {
          await _ledgerRepo.append(entry);
        }
      } on Exception {
        remoteSucceeded = false;
      }

      // Read from local repos (always available, even offline)
      final wallet = await _walletRepo.getByUserId(_userId);
      final history = await _ledgerRepo.getByUserId(_userId);
      emit(WalletLoaded(
        wallet: wallet,
        history: history,
        isOffline: !remoteSucceeded,
      ));
    } on Exception catch (e) {
      AppLogger.error('Wallet fetch failed', tag: 'WalletBloc', error: e);
      emit(WalletError(ErrorMessages.humanize(e)));
    }
  }
}
