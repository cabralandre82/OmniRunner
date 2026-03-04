import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';

sealed class WalletState extends Equatable {
  const WalletState();

  @override
  List<Object?> get props => [];
}

final class WalletInitial extends WalletState {
  const WalletInitial();
}

final class WalletLoading extends WalletState {
  const WalletLoading();
}

final class WalletLoaded extends WalletState {
  final WalletEntity wallet;
  final List<LedgerEntryEntity> history;
  final bool isOffline;

  const WalletLoaded({
    required this.wallet,
    required this.history,
    this.isOffline = false,
  });

  @override
  List<Object?> get props => [wallet, history, isOffline];
}

final class WalletError extends WalletState {
  final String message;

  const WalletError(this.message);

  @override
  List<Object?> get props => [message];
}
