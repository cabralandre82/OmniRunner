import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';
import 'package:omni_runner/domain/usecases/social/create_group.dart';

class _FakeGroupRepo implements IGroupRepo {
  int userGroupCount = 0;
  GroupEntity? savedGroup;
  GroupMemberEntity? savedMember;

  @override Future<int> countGroupsForUser(String u) async => userGroupCount;
  @override Future<void> saveGroup(GroupEntity g) async => savedGroup = g;
  @override Future<void> saveMember(GroupMemberEntity m) async => savedMember = m;
  @override Future<void> updateGroup(GroupEntity g) async {}
  @override Future<void> updateMember(GroupMemberEntity m) async {}
  @override Future<GroupEntity?> getGroupById(String id) async => null;
  @override Future<List<GroupEntity>> getGroupsByUserId(String u) async => [];
  @override Future<void> deleteGroup(String id) async {}
  @override Future<GroupMemberEntity?> getMember(String g, String u) async => null;
  @override Future<List<GroupMemberEntity>> getActiveMembers(String g) async => [];
  @override Future<int> countActiveMembers(String g) async => 0;
  @override Future<void> saveGoal(GroupGoalEntity g) async {}
  @override Future<void> updateGoal(GroupGoalEntity g) async {}
  @override Future<GroupGoalEntity?> getGoalById(String id) async => null;
  @override Future<List<GroupGoalEntity>> getActiveGoals(String g) async => [];
}

void main() {
  late _FakeGroupRepo repo;
  late CreateGroup usecase;
  int seq = 0;

  setUp(() {
    seq = 0;
    repo = _FakeGroupRepo();
    usecase = CreateGroup(groupRepo: repo);
  });

  test('creates group with creator as admin', () async {
    final group = await usecase.call(
      creatorUserId: 'u1', creatorDisplayName: 'Alice',
      name: 'Runners', uuidGenerator: () => 'id-${seq++}', nowMs: 1000,
    );
    expect(group.name, 'Runners');
    expect(repo.savedMember!.role, GroupRole.admin);
    expect(repo.savedMember!.userId, 'u1');
  });

  test('throws when user has 10 groups', () {
    repo.userGroupCount = 10;
    expect(
      () => usecase.call(
        creatorUserId: 'u1', creatorDisplayName: 'A',
        name: 'G', uuidGenerator: () => 'id', nowMs: 1000,
      ),
      throwsA(isA<GroupLimitReached>()),
    );
  });
}
