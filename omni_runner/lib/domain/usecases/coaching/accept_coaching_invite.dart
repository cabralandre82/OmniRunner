import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Accepts a pending coaching group invitation.
///
/// Validates:
/// - Invite exists and is pending.
/// - Invite has not expired.
/// - The accepting user is the invited user.
///
/// Creates a [CoachingMemberEntity] with [CoachingRole.athlete] and
/// transitions the invite to [CoachingInviteStatus.accepted].
///
/// Throws [CoachingFailure] on validation error.
final class AcceptCoachingInvite {
  final ICoachingInviteRepo _inviteRepo;
  final ICoachingMemberRepo _memberRepo;

  const AcceptCoachingInvite({
    required ICoachingInviteRepo inviteRepo,
    required ICoachingMemberRepo memberRepo,
  })  : _inviteRepo = inviteRepo,
        _memberRepo = memberRepo;

  Future<CoachingMemberEntity> call({
    required String inviteId,
    required String acceptingUserId,
    required String displayName,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final invite = await _inviteRepo.getById(inviteId);
    if (invite == null) throw CoachingInviteNotFound(inviteId);

    if (invite.status != CoachingInviteStatus.pending) {
      throw InvalidCoachingInviteStatus(
        inviteId,
        CoachingInviteStatus.pending.name,
        invite.status.name,
      );
    }

    if (invite.hasExpired(nowMs)) {
      await _inviteRepo.update(
        invite.copyWith(status: CoachingInviteStatus.expired),
      );
      throw CoachingInviteExpired(inviteId);
    }

    if (invite.invitedUserId != acceptingUserId) {
      throw InvalidCoachingInviteStatus(
        inviteId,
        'invitedUserId must match acceptingUserId',
        'wrong user',
      );
    }

    final member = CoachingMemberEntity(
      id: uuidGenerator(),
      userId: acceptingUserId,
      groupId: invite.groupId,
      displayName: displayName,
      role: CoachingRole.athlete,
      joinedAtMs: nowMs,
    );

    await _memberRepo.save(member);
    await _inviteRepo.update(
      invite.copyWith(status: CoachingInviteStatus.accepted),
    );

    return member;
  }
}
