import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Creates a new coaching group and adds the creator as coach member.
///
/// Validates:
/// - Coach has not exceeded the group ownership limit (5).
///
/// The creator is automatically added as the first member with [CoachingRole.adminMaster].
///
/// Throws [CoachingFailure] on validation error.
final class CreateCoachingGroup {
  final ICoachingGroupRepo _groupRepo;
  final ICoachingMemberRepo _memberRepo;

  static const _maxGroupsPerCoach = 5;

  const CreateCoachingGroup({
    required ICoachingGroupRepo groupRepo,
    required ICoachingMemberRepo memberRepo,
  })  : _groupRepo = groupRepo,
        _memberRepo = memberRepo;

  Future<CoachingGroupEntity> call({
    required String coachUserId,
    required String coachDisplayName,
    required String name,
    String description = '',
    String city = '',
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final count = await _groupRepo.countByCoachUserId(coachUserId);
    if (count >= _maxGroupsPerCoach) {
      throw const CoachingGroupLimitReached(_maxGroupsPerCoach);
    }

    final group = CoachingGroupEntity(
      id: uuidGenerator(),
      name: name,
      coachUserId: coachUserId,
      description: description,
      city: city,
      createdAtMs: nowMs,
    );

    final member = CoachingMemberEntity(
      id: uuidGenerator(),
      userId: coachUserId,
      groupId: group.id,
      displayName: coachDisplayName,
      role: CoachingRole.adminMaster,
      joinedAtMs: nowMs,
    );

    await _groupRepo.save(group);
    await _memberRepo.save(member);

    return group;
  }
}
