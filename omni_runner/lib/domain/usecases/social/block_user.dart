import 'package:omni_runner/domain/entities/friendship_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';

/// Blocks another user, removing any existing friendship.
///
/// If a friendship exists (any status), it is transitioned to [FriendshipStatus.blocked].
/// If no friendship exists, a new blocked record is created.
///
/// Blocking is asymmetric: A blocks B means A initiated the block.
/// Both users become invisible to each other in search, leaderboards, and feed.
///
/// See `docs/SOCIAL_SPEC.md` §2.3.
final class BlockUser {
  final IFriendshipRepo _friendshipRepo;

  const BlockUser({required IFriendshipRepo friendshipRepo})
      : _friendshipRepo = friendshipRepo;

  Future<FriendshipEntity> call({
    required String blockerUserId,
    required String blockedUserId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final existing =
        await _friendshipRepo.findBetween(blockerUserId, blockedUserId);

    if (existing != null) {
      if (existing.userIdA == blockerUserId) {
        final updated = existing.copyWith(status: FriendshipStatus.blocked);
        await _friendshipRepo.update(updated);
        return updated;
      }
      // Blocker is userIdB — reorient so blocker is always userIdA.
      await _friendshipRepo.deleteById(existing.id);
      final reoriented = FriendshipEntity(
        id: uuidGenerator(),
        userIdA: blockerUserId,
        userIdB: blockedUserId,
        status: FriendshipStatus.blocked,
        createdAtMs: nowMs,
      );
      await _friendshipRepo.save(reoriented);
      return reoriented;
    }

    final record = FriendshipEntity(
      id: uuidGenerator(),
      userIdA: blockerUserId,
      userIdB: blockedUserId,
      status: FriendshipStatus.blocked,
      createdAtMs: nowMs,
    );

    await _friendshipRepo.save(record);
    return record;
  }
}
