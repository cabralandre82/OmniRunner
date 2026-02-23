import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Sends an invitation for a user to join a coaching group.
///
/// Validates:
/// - Group exists.
/// - Caller is staff (admin_master, professor, or assistente).
/// - Invited user is not already a member.
/// - No pending invite already exists for this user in this group.
///
/// Invites expire after [_inviteTtlMs] (7 days).
///
/// Throws [CoachingFailure] on validation error.
final class InviteUserToGroup {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;
  final ICoachingInviteRepo _inviteRepo;

  static const _inviteTtlMs = 7 * 24 * 60 * 60 * 1000; // 7 days

  const InviteUserToGroup({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
    required ICoachingInviteRepo inviteRepo,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo,
        _inviteRepo = inviteRepo;

  Future<CoachingInviteEntity> call({
    required String groupId,
    required String callerUserId,
    required String invitedUserId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final group = await _groupRepo.getById(groupId);
    if (group == null) throw CoachingGroupNotFound(groupId);

    final caller = await _memberRepo.getMember(groupId, callerUserId);
    if (caller == null || !caller.isStaff) {
      throw InsufficientCoachingRole(
          callerUserId, groupId, 'staff (admin_master, professor, or assistente)');
    }

    final existing = await _memberRepo.getMember(groupId, invitedUserId);
    if (existing != null) {
      throw AlreadyCoachingMember(invitedUserId, groupId);
    }

    final pendingInvite = await _inviteRepo.findPending(groupId, invitedUserId);
    if (pendingInvite != null) {
      throw CoachingInviteAlreadyExists(invitedUserId, groupId);
    }

    final invite = CoachingInviteEntity(
      id: uuidGenerator(),
      groupId: groupId,
      invitedUserId: invitedUserId,
      invitedByUserId: callerUserId,
      status: CoachingInviteStatus.pending,
      expiresAtMs: nowMs + _inviteTtlMs,
      createdAtMs: nowMs,
    );

    await _inviteRepo.save(invite);
    return invite;
  }
}
