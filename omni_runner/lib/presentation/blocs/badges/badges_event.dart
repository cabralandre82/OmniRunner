import 'package:equatable/equatable.dart';

sealed class BadgesEvent extends Equatable {
  const BadgesEvent();

  @override
  List<Object?> get props => [];
}

final class LoadBadges extends BadgesEvent {
  final String userId;
  const LoadBadges(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshBadges extends BadgesEvent {
  const RefreshBadges();
}
