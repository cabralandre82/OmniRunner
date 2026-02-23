import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';

/// Contract for persisting and retrieving groups, members, and goals.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class IGroupRepo {
  // ── Group CRUD ──

  Future<void> saveGroup(GroupEntity group);

  Future<void> updateGroup(GroupEntity group);

  Future<GroupEntity?> getGroupById(String id);

  /// Groups where the user is an active member.
  Future<List<GroupEntity>> getGroupsByUserId(String userId);

  Future<void> deleteGroup(String id);

  // ── Members ──

  Future<void> saveMember(GroupMemberEntity member);

  Future<void> updateMember(GroupMemberEntity member);

  Future<GroupMemberEntity?> getMember(String groupId, String userId);

  /// All active members of a group.
  Future<List<GroupMemberEntity>> getActiveMembers(String groupId);

  Future<int> countActiveMembers(String groupId);

  /// How many groups the user is currently an active member of.
  Future<int> countGroupsForUser(String userId);

  // ── Goals ──

  Future<void> saveGoal(GroupGoalEntity goal);

  Future<void> updateGoal(GroupGoalEntity goal);

  Future<GroupGoalEntity?> getGoalById(String id);

  Future<List<GroupGoalEntity>> getActiveGoals(String groupId);
}
