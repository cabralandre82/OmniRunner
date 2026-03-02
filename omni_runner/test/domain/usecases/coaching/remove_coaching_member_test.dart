import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/remove_coaching_member.dart';

class _FakeMemberRepo implements ICoachingMemberRepo {
  final Map<String, CoachingMemberEntity?> _members = {};
  String? deletedId;

  void setMember(String groupId, String userId, CoachingMemberEntity? m) {
    _members['$groupId:$userId'] = m;
  }

  @override
  Future<CoachingMemberEntity?> getMember(String g, String u) async =>
      _members['$g:$u'];
  @override
  Future<void> deleteById(String id) async => deletedId = id;
  @override
  Future<void> save(CoachingMemberEntity m) async {}
  @override
  Future<void> update(CoachingMemberEntity m) async {}
  @override
  Future<List<CoachingMemberEntity>> getByGroupId(String g) async => [];
  @override
  Future<List<CoachingMemberEntity>> getByUserId(String u) async => [];
  @override
  Future<int> countByGroupId(String g) async => 0;
}

CoachingMemberEntity _member(String userId, CoachingRole role) =>
    CoachingMemberEntity(
      id: 'm-$userId',
      userId: userId,
      groupId: 'g1',
      displayName: userId,
      role: role,
      joinedAtMs: 0,
    );

void main() {
  late _FakeMemberRepo repo;
  late RemoveCoachingMember usecase;

  setUp(() {
    repo = _FakeMemberRepo();
    usecase = RemoveCoachingMember(memberRepo: repo);
  });

  test('admin_master removes athlete successfully', () async {
    repo.setMember('g1', 'coach', _member('coach', CoachingRole.adminMaster));
    repo.setMember('g1', 'athlete', _member('athlete', CoachingRole.atleta));

    await usecase.call(
      groupId: 'g1',
      callerUserId: 'coach',
      targetUserId: 'athlete',
    );

    expect(repo.deletedId, 'm-athlete');
  });

  test('throws when caller is not staff', () {
    repo.setMember('g1', 'user', _member('user', CoachingRole.atleta));
    repo.setMember('g1', 'other', _member('other', CoachingRole.atleta));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'user',
        targetUserId: 'other',
      ),
      throwsA(isA<InsufficientCoachingRole>()),
    );
  });

  test('throws when target not found', () {
    repo.setMember('g1', 'coach', _member('coach', CoachingRole.adminMaster));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'coach',
        targetUserId: 'unknown',
      ),
      throwsA(isA<NotCoachingMember>()),
    );
  });

  test('throws when trying to remove admin_master', () {
    repo.setMember('g1', 'prof', _member('prof', CoachingRole.professor));
    repo.setMember('g1', 'coach', _member('coach', CoachingRole.adminMaster));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'prof',
        targetUserId: 'coach',
      ),
      throwsA(isA<CannotRemoveAdminMaster>()),
    );
  });

  test('assistente cannot remove other staff', () {
    repo.setMember('g1', 'ast', _member('ast', CoachingRole.assistente));
    repo.setMember('g1', 'prof', _member('prof', CoachingRole.professor));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'ast',
        targetUserId: 'prof',
      ),
      throwsA(isA<InsufficientCoachingRole>()),
    );
  });
}
