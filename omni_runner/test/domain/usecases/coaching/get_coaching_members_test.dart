import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_members.dart';

final _group = CoachingGroupEntity(id: 'g1', name: 'G', coachUserId: 'coach', createdAtMs: 0);
final _caller = CoachingMemberEntity(id: 'm1', userId: 'coach', groupId: 'g1', displayName: 'C', role: CoachingRole.adminMaster, joinedAtMs: 0);

class _FakeGroupRepo implements ICoachingGroupRepo {
  @override Future<CoachingGroupEntity?> getById(String id) async => id == 'g1' ? _group : null;
  @override Future<void> save(CoachingGroupEntity g) async {}
  @override Future<void> update(CoachingGroupEntity g) async {}
  @override Future<List<CoachingGroupEntity>> getByCoachUserId(String u) async => [];
  @override Future<int> countByCoachUserId(String u) async => 0;
  @override Future<void> deleteById(String id) async {}
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  @override Future<CoachingMemberEntity?> getMember(String g, String u) async => u == 'coach' ? _caller : null;
  @override Future<List<CoachingMemberEntity>> getByGroupId(String g) async => [_caller];
  @override Future<void> save(CoachingMemberEntity m) async {}
  @override Future<void> update(CoachingMemberEntity m) async {}
  @override Future<List<CoachingMemberEntity>> getByUserId(String u) async => [];
  @override Future<int> countByGroupId(String g) async => 1;
  @override Future<void> deleteById(String id) async {}
}

void main() {
  late GetCoachingMembers usecase;

  setUp(() {
    usecase = GetCoachingMembers(groupRepo: _FakeGroupRepo(), memberRepo: _FakeMemberRepo());
  });

  test('returns members when caller is a member', () async {
    final members = await usecase.call(groupId: 'g1', callerUserId: 'coach');
    expect(members, hasLength(1));
  });

  test('throws when group not found', () {
    expect(() => usecase.call(groupId: 'x', callerUserId: 'coach'), throwsA(isA<CoachingGroupNotFound>()));
  });

  test('throws when caller not a member', () {
    expect(() => usecase.call(groupId: 'g1', callerUserId: 'stranger'), throwsA(isA<NotCoachingMember>()));
  });
}
