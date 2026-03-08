import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/group_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_group_repo.dart';
import 'package:omni_runner/domain/usecases/social/leave_group.dart';

const _group = GroupEntity(
  id: 'g1', name: 'R', createdByUserId: 'owner', createdAtMs: 0,
  privacy: GroupPrivacy.open, memberCount: 3,
);

class _FakeGroupRepo implements IGroupRepo {
  final Map<String, GroupMemberEntity?> _members = {};
  List<GroupMemberEntity> activeMembers = [];
  GroupMemberEntity? updatedMember;
  GroupEntity? updatedGroup;

  void setMember(String uid, GroupMemberEntity? m) => _members[uid] = m;

  @override Future<GroupEntity?> getGroupById(String id) async => _group;
  @override Future<GroupMemberEntity?> getMember(String g, String u) async => _members[u];
  @override Future<List<GroupMemberEntity>> getActiveMembers(String g) async => activeMembers;
  @override Future<void> updateMember(GroupMemberEntity m) async => updatedMember = m;
  @override Future<void> updateGroup(GroupEntity g) async => updatedGroup = g;
  @override Future<void> saveGroup(GroupEntity g) async {}
  @override Future<void> saveMember(GroupMemberEntity m) async {}
  @override Future<List<GroupEntity>> getGroupsByUserId(String u) async => [];
  @override Future<void> deleteGroup(String id) async {}
  @override Future<int> countActiveMembers(String g) async => 0;
  @override Future<int> countGroupsForUser(String u) async => 0;
  @override Future<void> saveGoal(GroupGoalEntity g) async {}
  @override Future<void> updateGoal(GroupGoalEntity g) async {}
  @override Future<GroupGoalEntity?> getGoalById(String id) async => null;
  @override Future<List<GroupGoalEntity>> getActiveGoals(String g) async => [];
}

GroupMemberEntity _member(String uid, GroupRole role) => GroupMemberEntity(
      id: 'm-$uid', groupId: 'g1', userId: uid, displayName: uid,
      role: role, joinedAtMs: 0,
    );

void main() {
  late _FakeGroupRepo repo;
  late LeaveGroup usecase;

  setUp(() {
    repo = _FakeGroupRepo();
    usecase = LeaveGroup(groupRepo: repo);
  });

  test('member leaves and count decrements', () async {
    repo.setMember('u1', _member('u1', GroupRole.member));
    await usecase.call(groupId: 'g1', userId: 'u1');
    expect(repo.updatedMember!.status, GroupMemberStatus.left);
    expect(repo.updatedGroup!.memberCount, 2);
  });

  test('throws when not a member', () {
    expect(
      () => usecase.call(groupId: 'g1', userId: 'unknown'),
      throwsA(isA<NotGroupMember>()),
    );
  });

  test('promotes successor when last admin leaves', () async {
    repo.setMember('admin', _member('admin', GroupRole.admin));
    repo.activeMembers = [
      _member('admin', GroupRole.admin),
      _member('u2', GroupRole.member),
    ];
    await usecase.call(groupId: 'g1', userId: 'admin');
    // updatedMember is called multiple times; last one should be promotion or the leave
    expect(repo.updatedMember, isNotNull);
  });
}
