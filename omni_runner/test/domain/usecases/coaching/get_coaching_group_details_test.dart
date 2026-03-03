import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';

final _group = CoachingGroupEntity(id: 'g1', name: 'G', coachUserId: 'coach', createdAtMs: 0);
final _member = CoachingMemberEntity(id: 'm1', userId: 'u1', groupId: 'g1', displayName: 'U', role: CoachingRole.athlete, joinedAtMs: 0);

class _FakeGroupRepo implements ICoachingGroupRepo {
  @override Future<CoachingGroupEntity?> getById(String id) async => id == 'g1' ? _group : null;
  @override Future<void> save(CoachingGroupEntity g) async {}
  @override Future<void> update(CoachingGroupEntity g) async {}
  @override Future<List<CoachingGroupEntity>> getByCoachUserId(String u) async => [];
  @override Future<int> countByCoachUserId(String u) async => 0;
  @override Future<void> deleteById(String id) async {}
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  final Map<String, CoachingMemberEntity?> _members = {};
  List<CoachingMemberEntity> groupMembers = [];

  void setMember(String uid, CoachingMemberEntity? m) => _members['g1:$uid'] = m;

  @override Future<CoachingMemberEntity?> getMember(String g, String u) async => _members['$g:$u'];
  @override Future<List<CoachingMemberEntity>> getByGroupId(String g) async => groupMembers;
  @override Future<void> save(CoachingMemberEntity m) async {}
  @override Future<void> update(CoachingMemberEntity m) async {}
  @override Future<List<CoachingMemberEntity>> getByUserId(String u) async => [];
  @override Future<int> countByGroupId(String g) async => 0;
  @override Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeGroupRepo groupRepo;
  late _FakeMemberRepo memberRepo;
  late GetCoachingGroupDetails usecase;

  setUp(() {
    groupRepo = _FakeGroupRepo();
    memberRepo = _FakeMemberRepo()..setMember('u1', _member)..groupMembers = [_member];
    usecase = GetCoachingGroupDetails(groupRepo: groupRepo, memberRepo: memberRepo);
  });

  test('returns group details', () async {
    final details = await usecase.call(groupId: 'g1', callerUserId: 'u1');
    expect(details.group.id, 'g1');
    expect(details.members, hasLength(1));
    expect(details.memberCount, 1);
  });

  test('throws when group not found', () {
    expect(
      () => usecase.call(groupId: 'unknown', callerUserId: 'u1'),
      throwsA(isA<CoachingGroupNotFound>()),
    );
  });

  test('throws when caller not a member', () {
    expect(
      () => usecase.call(groupId: 'g1', callerUserId: 'stranger'),
      throwsA(isA<NotCoachingMember>()),
    );
  });
}
