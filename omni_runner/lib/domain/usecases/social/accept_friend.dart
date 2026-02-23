import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';

/// Accepts a pending friend request.
///
/// Only the recipient (userIdB) can accept.
/// Both users' friend counts are validated against the 500 limit.
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §2.3.
final class AcceptFriend {
  final IFriendshipRepo _friendshipRepo;

  static const _maxFriends = 500;

  const AcceptFriend({required IFriendshipRepo friendshipRepo})
      : _friendshipRepo = friendshipRepo;

  Future<FriendshipEntity> call({
    required String friendshipId,
    required String acceptingUserId,
    required int nowMs,
  }) async {
    final friendship = await _friendshipRepo.getById(friendshipId);
    if (friendship == null) {
      throw FriendshipNotFound(friendshipId);
    }

    if (friendship.status != FriendshipStatus.pending) {
      throw InvalidFriendshipStatus(
        friendshipId,
        FriendshipStatus.pending.name,
        friendship.status.name,
      );
    }

    if (friendship.userIdB != acceptingUserId) {
      throw InvalidFriendshipStatus(
        friendshipId,
        'recipient must be acceptingUserId',
        'wrong user',
      );
    }

    final countA = await _friendshipRepo.countAccepted(friendship.userIdA);
    if (countA >= _maxFriends) {
      throw const FriendLimitReached(_maxFriends);
    }

    final countB = await _friendshipRepo.countAccepted(friendship.userIdB);
    if (countB >= _maxFriends) {
      throw const FriendLimitReached(_maxFriends);
    }

    final updated = friendship.copyWith(
      status: FriendshipStatus.accepted,
      acceptedAtMs: nowMs,
    );

    await _friendshipRepo.update(updated);
    return updated;
  }
}
