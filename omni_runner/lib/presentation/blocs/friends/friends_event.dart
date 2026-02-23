import 'package:equatable/equatable.dart';

sealed class FriendsEvent extends Equatable {
  const FriendsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadFriends extends FriendsEvent {
  final String userId;
  const LoadFriends(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshFriends extends FriendsEvent {
  const RefreshFriends();
}
