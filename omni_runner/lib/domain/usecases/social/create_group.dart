import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';

/// Creates a new group and adds the creator as admin.
///
/// Validates:
/// - User has not exceeded the group limit (10).
/// - maxMembers ≤ 200.
///
/// Creator is automatically added as the first admin member.
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §3.
final class CreateGroup {
  final IGroupRepo _groupRepo;

  static const _maxGroupsPerUser = 10;
  static const _hardMaxMembers = 200;

  const CreateGroup({required IGroupRepo groupRepo})
      : _groupRepo = groupRepo;

  Future<GroupEntity> call({
    required String creatorUserId,
    required String creatorDisplayName,
    required String name,
    String description = '',
    GroupPrivacy privacy = GroupPrivacy.open,
    int maxMembers = 100,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final userGroupCount =
        await _groupRepo.countGroupsForUser(creatorUserId);
    if (userGroupCount >= _maxGroupsPerUser) {
      throw const GroupLimitReached(_maxGroupsPerUser);
    }

    final clampedMax = maxMembers.clamp(2, _hardMaxMembers);

    final group = GroupEntity(
      id: uuidGenerator(),
      name: name,
      description: description,
      createdByUserId: creatorUserId,
      createdAtMs: nowMs,
      privacy: privacy,
      maxMembers: clampedMax,
      memberCount: 1,
    );

    final member = GroupMemberEntity(
      id: uuidGenerator(),
      groupId: group.id,
      userId: creatorUserId,
      displayName: creatorDisplayName,
      role: GroupRole.admin,
      joinedAtMs: nowMs,
    );

    await _groupRepo.saveGroup(group);
    await _groupRepo.saveMember(member);

    return group;
  }
}
