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

final class AcceptFriendEvent extends FriendsEvent {
  final String friendshipId;
  const AcceptFriendEvent(this.friendshipId);

  @override
  List<Object?> get props => [friendshipId];
}

final class DeclineFriendEvent extends FriendsEvent {
  final String friendshipId;
  const DeclineFriendEvent(this.friendshipId);

  @override
  List<Object?> get props => [friendshipId];
}

final class SendFriendRequest extends FriendsEvent {
  final String toUserId;
  const SendFriendRequest(this.toUserId);

  @override
  List<Object?> get props => [toUserId];
}
