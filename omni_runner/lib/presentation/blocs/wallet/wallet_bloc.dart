import 'package:flutter_bloc/flutter_bloc.dart';
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
      final wallet = await _walletRepo.getByUserId(_userId);
      final history = await _ledgerRepo.getByUserId(_userId);
      emit(WalletLoaded(wallet: wallet, history: history));
    } on Exception catch (e) {
      emit(WalletError('Erro ao carregar OmniCoins: $e'));
    }
  }
}
