import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';

/// Adds a user as a member of an existing group.
///
/// Validates:
/// - Group exists.
/// - Group is not full.
/// - User is not already an active member.
/// - User is not banned from the group.
/// - User has not exceeded the group limit (10).
///
/// For [GroupPrivacy.closed] groups, the caller is responsible for
/// verifying admin/mod approval before calling this use case.
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §3.4.
final class JoinGroup {
  final IGroupRepo _groupRepo;

  static const _maxGroupsPerUser = 10;

  const JoinGroup({required IGroupRepo groupRepo})
      : _groupRepo = groupRepo;

  Future<GroupMemberEntity> call({
    required String groupId,
    required String userId,
    required String displayName,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final group = await _groupRepo.getGroupById(groupId);
    if (group == null) throw GroupNotFound(groupId);

    if (group.isFull) throw GroupFull(groupId, group.maxMembers);

    final existing = await _groupRepo.getMember(groupId, userId);
    if (existing != null) {
      if (existing.status == GroupMemberStatus.banned) {
        throw UserBannedFromGroup(userId, groupId);
      }
      if (existing.status == GroupMemberStatus.active) {
        throw AlreadyGroupMember(userId, groupId);
      }
      if (existing.status == GroupMemberStatus.left) {
        final userGroupCount = await _groupRepo.countGroupsForUser(userId);
        if (userGroupCount >= _maxGroupsPerUser) {
          throw const GroupLimitReached(_maxGroupsPerUser);
        }
        final reactivated = existing.copyWith(
          displayName: displayName,
          role: GroupRole.member,
          status: GroupMemberStatus.active,
        );
        await _groupRepo.updateMember(reactivated);
        await _groupRepo.updateGroup(
          group.copyWith(memberCount: group.memberCount + 1),
        );
        return reactivated;
      }
    }

    final userGroupCount = await _groupRepo.countGroupsForUser(userId);
    if (userGroupCount >= _maxGroupsPerUser) {
      throw const GroupLimitReached(_maxGroupsPerUser);
    }

    final member = GroupMemberEntity(
      id: uuidGenerator(),
      groupId: groupId,
      userId: userId,
      displayName: displayName,
      role: GroupRole.member,
      joinedAtMs: nowMs,
    );

    await _groupRepo.saveMember(member);
    await _groupRepo.updateGroup(
      group.copyWith(memberCount: group.memberCount + 1),
    );

    return member;
  }
}
