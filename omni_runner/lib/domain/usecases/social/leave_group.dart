import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';

/// Removes a user from a group.
///
/// If the leaving user is the last admin, the longest-standing active
/// member is promoted to admin automatically.
///
/// Member status is set to [GroupMemberStatus.left] and group
/// member count is decremented.
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §3.4.
final class LeaveGroup {
  final IGroupRepo _groupRepo;

  const LeaveGroup({required IGroupRepo groupRepo})
      : _groupRepo = groupRepo;

  Future<void> call({
    required String groupId,
    required String userId,
  }) async {
    final group = await _groupRepo.getGroupById(groupId);
    if (group == null) throw GroupNotFound(groupId);

    final member = await _groupRepo.getMember(groupId, userId);
    if (member == null || member.status != GroupMemberStatus.active) {
      throw NotGroupMember(userId, groupId);
    }

    // If leaving user is admin, try to promote successor.
    if (member.role == GroupRole.admin) {
      await _promoteSuccessorIfNeeded(groupId, userId);
    }

    await _groupRepo.updateMember(
      member.copyWith(status: GroupMemberStatus.left),
    );

    final newCount = (group.memberCount - 1).clamp(0, group.maxMembers);
    await _groupRepo.updateGroup(
      group.copyWith(memberCount: newCount),
    );
  }

  Future<void> _promoteSuccessorIfNeeded(
    String groupId,
    String leavingUserId,
  ) async {
    final members = await _groupRepo.getActiveMembers(groupId);
    final admins = members
        .where((m) => m.role == GroupRole.admin && m.userId != leavingUserId)
        .toList();

    if (admins.isNotEmpty) return;

    // No other admins — promote the oldest non-leaving active member.
    final candidates = members
        .where((m) => m.userId != leavingUserId)
        .toList()
      ..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs));

    if (candidates.isNotEmpty) {
      await _groupRepo.updateMember(
        candidates.first.copyWith(role: GroupRole.admin),
      );
    }
  }
}
