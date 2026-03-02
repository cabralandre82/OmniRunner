import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/create_coaching_group.dart';

class _FakeGroupRepo implements ICoachingGroupRepo {
  int ownerCount = 0;
  CoachingGroupEntity? saved;

  @override
  Future<int> countByCoachUserId(String u) async => ownerCount;
  @override
  Future<void> save(CoachingGroupEntity g) async => saved = g;
  @override
  Future<void> update(CoachingGroupEntity g) async {}
  @override
  Future<CoachingGroupEntity?> getById(String id) async => null;
  @override
  Future<List<CoachingGroupEntity>> getByCoachUserId(String u) async => [];
  @override
  Future<void> deleteById(String id) async {}
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  CoachingMemberEntity? saved;

  @override
  Future<void> save(CoachingMemberEntity m) async => saved = m;
  @override
  Future<void> update(CoachingMemberEntity m) async {}
  @override
  Future<CoachingMemberEntity?> getMember(String g, String u) async => null;
  @override
  Future<List<CoachingMemberEntity>> getByGroupId(String g) async => [];
  @override
  Future<List<CoachingMemberEntity>> getByUserId(String u) async => [];
  @override
  Future<int> countByGroupId(String g) async => 0;
  @override
  Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeGroupRepo groupRepo;
  late _FakeMemberRepo memberRepo;
  late CreateCoachingGroup usecase;

  int seq = 0;
  String nextId() => 'uuid-${seq++}';

  setUp(() {
    seq = 0;
    groupRepo = _FakeGroupRepo();
    memberRepo = _FakeMemberRepo();
    usecase = CreateCoachingGroup(
      groupRepo: groupRepo,
      memberRepo: memberRepo,
    );
  });

  test('creates group and adds coach as admin_master member', () async {
    final group = await usecase.call(
      coachUserId: 'coach-1',
      coachDisplayName: 'Coach Maria',
      name: 'Grupo de Corrida',
      uuidGenerator: nextId,
      nowMs: 1000,
    );

    expect(group.coachUserId, 'coach-1');
    expect(group.name, 'Grupo de Corrida');
    expect(groupRepo.saved, isNotNull);
    expect(memberRepo.saved!.role, CoachingRole.adminMaster);
    expect(memberRepo.saved!.userId, 'coach-1');
    expect(memberRepo.saved!.groupId, group.id);
  });

  test('throws when coach has 5 groups already', () {
    groupRepo.ownerCount = 5;

    expect(
      () => usecase.call(
        coachUserId: 'coach-1',
        coachDisplayName: 'Coach',
        name: 'Group',
        uuidGenerator: nextId,
        nowMs: 1000,
      ),
      throwsA(isA<CoachingGroupLimitReached>()),
    );
  });
}
