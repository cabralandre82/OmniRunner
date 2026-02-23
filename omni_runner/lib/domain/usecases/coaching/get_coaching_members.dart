import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Retrieves all members of a coaching group.
///
/// Validates:
/// - Group exists.
/// - Caller is a member of the group (any role).
///
/// Returns members ordered by role (coach first) then joinedAt.
///
/// Throws [CoachingFailure] on validation error.
final class GetCoachingMembers {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;

  const GetCoachingMembers({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo;

  Future<List<CoachingMemberEntity>> call({
    required String groupId,
    required String callerUserId,
  }) async {
    final group = await _groupRepo.getById(groupId);
    if (group == null) throw CoachingGroupNotFound(groupId);

    final caller = await _memberRepo.getMember(groupId, callerUserId);
    if (caller == null) {
      throw NotCoachingMember(callerUserId, groupId);
    }

    return _memberRepo.getByGroupId(groupId);
  }
}
