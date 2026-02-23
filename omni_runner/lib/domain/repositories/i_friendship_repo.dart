import 'package:omni_runner/domain/entities/friendship_entity.dart';

/// Contract for persisting and retrieving friendships.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class IFriendshipRepo {
  Future<void> save(FriendshipEntity friendship);

  Future<void> update(FriendshipEntity friendship);

  Future<FriendshipEntity?> getById(String id);

  /// Returns all friendships where the user is either side (A or B).
  Future<List<FriendshipEntity>> getByUserId(String userId);

  /// Returns accepted friendships only.
  Future<List<FriendshipEntity>> getAcceptedByUserId(String userId);

  /// Returns pending requests where [userId] is the recipient (userIdB).
  Future<List<FriendshipEntity>> getPendingForUser(String userId);

  /// Finds an existing friendship between two users (any status except blocked).
  Future<FriendshipEntity?> findBetween(String userIdA, String userIdB);

  /// Checks if one user has blocked the other (either direction).
  Future<bool> isBlocked(String userIdA, String userIdB);

  /// Count of accepted friendships for a user.
  Future<int> countAccepted(String userId);

  /// Count of pending requests sent by a user.
  Future<int> countPendingSent(String userId);

  Future<void> deleteById(String id);
}
