import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Removes a member from a coaching group.
///
/// Validates:
/// - Group member exists.
/// - Caller has management role (admin_master or professor).
/// - Target is not the admin_master (owner cannot be removed).
/// - Assistentes cannot remove other staff members.
///
/// Throws [CoachingFailure] on validation error.
final class RemoveCoachingMember {
  final ICoachingMemberRepo _memberRepo;

  const RemoveCoachingMember({required ICoachingMemberRepo memberRepo})
      : _memberRepo = memberRepo;

  Future<void> call({
    required String groupId,
    required String callerUserId,
    required String targetUserId,
  }) async {
    final caller = await _memberRepo.getMember(groupId, callerUserId);
    if (caller == null || !caller.isStaff) {
      throw InsufficientCoachingRole(
          callerUserId, groupId, 'staff (admin_master, professor, or assistente)');
    }

    final target = await _memberRepo.getMember(groupId, targetUserId);
    if (target == null) {
      throw NotCoachingMember(targetUserId, groupId);
    }

    if (target.role == CoachingRole.adminMaster) {
      throw CannotRemoveAdminMaster(groupId);
    }

    // Only admin_master/professor can remove other staff
    if (!caller.canManage && target.isStaff) {
      throw InsufficientCoachingRole(
          callerUserId, groupId, 'admin_master or professor');
    }

    await _memberRepo.deleteById(target.id);
  }
}
