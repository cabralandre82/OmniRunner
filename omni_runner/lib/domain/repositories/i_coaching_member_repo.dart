import 'package:omni_runner/domain/entities/coaching_member_entity.dart';

/// Contract for persisting and retrieving coaching group members.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class ICoachingMemberRepo {
  Future<void> save(CoachingMemberEntity member);

  Future<void> update(CoachingMemberEntity member);

  Future<CoachingMemberEntity?> getMember(String groupId, String userId);

  /// All members of a coaching group, ordered by role then joinedAt.
  Future<List<CoachingMemberEntity>> getByGroupId(String groupId);

  /// All coaching groups this user belongs to (as any role).
  Future<List<CoachingMemberEntity>> getByUserId(String userId);

  Future<int> countByGroupId(String groupId);

  Future<void> deleteById(String id);
}
