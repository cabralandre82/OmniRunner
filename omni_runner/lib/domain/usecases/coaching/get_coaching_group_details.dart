import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Aggregated result for a coaching group detail view.
final class CoachingGroupDetails {
  final CoachingGroupEntity group;
  final List<CoachingMemberEntity> members;
  final int memberCount;

  const CoachingGroupDetails({
    required this.group,
    required this.members,
    required this.memberCount,
  });
}

/// Retrieves a coaching group with its full member list.
///
/// Validates:
/// - Group exists.
/// - Caller is a member of the group (any role).
///
/// Returns an aggregated [CoachingGroupDetails] object.
///
/// Throws [CoachingFailure] on validation error.
final class GetCoachingGroupDetails {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;

  const GetCoachingGroupDetails({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo;

  Future<CoachingGroupDetails> call({
    required String groupId,
    required String callerUserId,
  }) async {
    final group = await _groupRepo.getById(groupId);
    if (group == null) throw CoachingGroupNotFound(groupId);

    final caller = await _memberRepo.getMember(groupId, callerUserId);
    if (caller == null) {
      throw NotCoachingMember(callerUserId, groupId);
    }

    final members = await _memberRepo.getByGroupId(groupId);

    return CoachingGroupDetails(
      group: group,
      members: members,
      memberCount: members.length,
    );
  }
}
