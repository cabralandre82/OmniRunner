import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';
import 'package:omni_runner/domain/usecases/social/join_group.dart';

const _group = GroupEntity(
  id: 'g1', name: 'Runners', createdByUserId: 'owner',
  createdAtMs: 0, privacy: GroupPrivacy.open, memberCount: 5, maxMembers: 100,
);

class _FakeGroupRepo implements IGroupRepo {
  GroupMemberEntity? existingMember;
  int userGroupCount = 0;
  GroupMemberEntity? savedMember;

  @override Future<GroupEntity?> getGroupById(String id) async => id == 'g1' ? _group : null;
  @override Future<GroupMemberEntity?> getMember(String g, String u) async => existingMember;
  @override Future<int> countGroupsForUser(String u) async => userGroupCount;
  @override Future<void> saveMember(GroupMemberEntity m) async => savedMember = m;
  @override Future<void> updateGroup(GroupEntity g) async {}
  @override Future<void> updateMember(GroupMemberEntity m) async {}
  @override Future<void> saveGroup(GroupEntity g) async {}
  @override Future<List<GroupEntity>> getGroupsByUserId(String u) async => [];
  @override Future<void> deleteGroup(String id) async {}
  @override Future<List<GroupMemberEntity>> getActiveMembers(String g) async => [];
  @override Future<int> countActiveMembers(String g) async => 0;
  @override Future<void> saveGoal(GroupGoalEntity g) async {}
  @override Future<void> updateGoal(GroupGoalEntity g) async {}
  @override Future<GroupGoalEntity?> getGoalById(String id) async => null;
  @override Future<List<GroupGoalEntity>> getActiveGoals(String g) async => [];
}

void main() {
  late _FakeGroupRepo repo;
  late JoinGroup usecase;

  setUp(() {
    repo = _FakeGroupRepo();
    usecase = JoinGroup(groupRepo: repo);
  });

  test('joins group successfully', () async {
    final member = await usecase.call(
      groupId: 'g1', userId: 'u1', displayName: 'Bob',
      uuidGenerator: () => 'm-id', nowMs: 1000,
    );
    expect(member.role, GroupRole.member);
    expect(repo.savedMember, isNotNull);
  });

  test('throws when group not found', () {
    expect(
      () => usecase.call(groupId: 'unknown', userId: 'u1', displayName: 'B', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<GroupNotFound>()),
    );
  });

  test('throws when already active member', () {
    repo.existingMember = const GroupMemberEntity(
      id: 'm1', groupId: 'g1', userId: 'u1', displayName: 'B',
      role: GroupRole.member, joinedAtMs: 0,
    );
    expect(
      () => usecase.call(groupId: 'g1', userId: 'u1', displayName: 'B', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<AlreadyGroupMember>()),
    );
  });

  test('throws when banned', () {
    repo.existingMember = const GroupMemberEntity(
      id: 'm1', groupId: 'g1', userId: 'u1', displayName: 'B',
      role: GroupRole.member, status: GroupMemberStatus.banned, joinedAtMs: 0,
    );
    expect(
      () => usecase.call(groupId: 'g1', userId: 'u1', displayName: 'B', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<UserBannedFromGroup>()),
    );
  });

  test('throws when user has 10 groups', () {
    repo.userGroupCount = 10;
    expect(
      () => usecase.call(groupId: 'g1', userId: 'u1', displayName: 'B', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<GroupLimitReached>()),
    );
  });
}
