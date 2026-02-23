import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';

/// Contract for persisting and retrieving coaching group invitations.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class ICoachingInviteRepo {
  Future<void> save(CoachingInviteEntity invite);

  Future<void> update(CoachingInviteEntity invite);

  Future<CoachingInviteEntity?> getById(String id);

  /// Pending invites for a specific user.
  Future<List<CoachingInviteEntity>> getPendingByUserId(String userId);

  /// All invites for a coaching group.
  Future<List<CoachingInviteEntity>> getByGroupId(String groupId);

  /// Find an existing pending invite for a user in a group.
  Future<CoachingInviteEntity?> findPending(String groupId, String userId);

  Future<void> deleteById(String id);
}
