import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';

sealed class FriendsState extends Equatable {
  const FriendsState();

  @override
  List<Object?> get props => [];
}

final class FriendsInitial extends FriendsState {
  const FriendsInitial();
}

final class FriendsLoading extends FriendsState {
  const FriendsLoading();
}

final class FriendsLoaded extends FriendsState {
  final String userId;
  final List<FriendshipEntity> accepted;
  final List<FriendshipEntity> pendingReceived;
  final List<FriendshipEntity> pendingSent;

  const FriendsLoaded({
    required this.userId,
    required this.accepted,
    this.pendingReceived = const [],
    this.pendingSent = const [],
  });

  int get totalFriends => accepted.length;

  @override
  List<Object?> get props => [userId, accepted, pendingReceived, pendingSent];
}

final class FriendsError extends FriendsState {
  final String message;
  const FriendsError(this.message);

  @override
  List<Object?> get props => [message];
}
