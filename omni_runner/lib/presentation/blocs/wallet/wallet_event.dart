import 'package:equatable/equatable.dart';

sealed class WalletEvent extends Equatable {
  const WalletEvent();

  @override
  List<Object?> get props => [];
}

final class LoadWallet extends WalletEvent {
  final String userId;
  const LoadWallet(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshWallet extends WalletEvent {
  const RefreshWallet();
}
