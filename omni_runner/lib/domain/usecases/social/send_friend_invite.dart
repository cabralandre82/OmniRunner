import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';

/// Sends a friend request from one user to another.
///
/// Validates:
/// - Not self-friending.
/// - No existing friendship/request between the pair.
/// - Neither user has blocked the other.
/// - Sender has not exceeded the pending request limit (50).
/// - Sender has not exceeded the friend limit (500).
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §2.3.
final class SendFriendInvite {
  final IFriendshipRepo _friendshipRepo;

  static const _maxPendingSent = 50;
  static const _maxFriends = 500;

  const SendFriendInvite({required IFriendshipRepo friendshipRepo})
      : _friendshipRepo = friendshipRepo;

  Future<FriendshipEntity> call({
    required String fromUserId,
    required String toUserId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    if (fromUserId == toUserId) {
      throw const CannotFriendSelf();
    }

    if (await _friendshipRepo.isBlocked(fromUserId, toUserId)) {
      throw UserIsBlocked(fromUserId, toUserId);
    }

    final existing = await _friendshipRepo.findBetween(fromUserId, toUserId);
    if (existing != null) {
      if (existing.status == FriendshipStatus.declined) {
        final reactivated = FriendshipEntity(
          id: existing.id,
          userIdA: fromUserId,
          userIdB: toUserId,
          status: FriendshipStatus.pending,
          createdAtMs: nowMs,
        );
        await _friendshipRepo.update(reactivated);
        return reactivated;
      }
      throw FriendshipAlreadyExists(fromUserId, toUserId);
    }

    final pendingCount = await _friendshipRepo.countPendingSent(fromUserId);
    if (pendingCount >= _maxPendingSent) {
      throw const FriendRequestLimitReached(_maxPendingSent);
    }

    final friendCount = await _friendshipRepo.countAccepted(fromUserId);
    if (friendCount >= _maxFriends) {
      throw const FriendLimitReached(_maxFriends);
    }

    final friendship = FriendshipEntity(
      id: uuidGenerator(),
      userIdA: fromUserId,
      userIdB: toUserId,
      status: FriendshipStatus.pending,
      createdAtMs: nowMs,
    );

    await _friendshipRepo.save(friendship);
    return friendship;
  }
}
