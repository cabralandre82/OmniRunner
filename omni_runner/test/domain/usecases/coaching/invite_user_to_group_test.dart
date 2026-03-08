import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/invite_user_to_group.dart';

const _group = CoachingGroupEntity(
  id: 'g1',
  name: 'Grupo',
  coachUserId: 'coach',
  createdAtMs: 0,
);

const _staffMember = CoachingMemberEntity(
  id: 'm-coach',
  userId: 'coach',
  groupId: 'g1',
  displayName: 'Coach',
  role: CoachingRole.adminMaster,
  joinedAtMs: 0,
);

class _FakeGroupRepo implements ICoachingGroupRepo {
  @override
  Future<CoachingGroupEntity?> getById(String id) async =>
      id == 'g1' ? _group : null;
  @override
  Future<void> save(CoachingGroupEntity g) async {}
  @override
  Future<void> update(CoachingGroupEntity g) async {}
  @override
  Future<List<CoachingGroupEntity>> getByCoachUserId(String u) async => [];
  @override
  Future<int> countByCoachUserId(String u) async => 0;
  @override
  Future<void> deleteById(String id) async {}
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  final Map<String, CoachingMemberEntity?> _members = {};

  void setMember(String groupId, String userId, CoachingMemberEntity? m) {
    _members['$groupId:$userId'] = m;
  }

  @override
  Future<CoachingMemberEntity?> getMember(String g, String u) async =>
      _members['$g:$u'];
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
  @override
  Future<void> deleteById(String id) async {}
}

class _FakeInviteRepo implements ICoachingInviteRepo {
  CoachingInviteEntity? pendingInvite;
  CoachingInviteEntity? saved;

  @override
  Future<CoachingInviteEntity?> findPending(String g, String u) async =>
      pendingInvite;
  @override
  Future<void> save(CoachingInviteEntity i) async => saved = i;
  @override
  Future<void> update(CoachingInviteEntity i) async {}
  @override
  Future<CoachingInviteEntity?> getById(String id) async => null;
  @override
  Future<List<CoachingInviteEntity>> getPendingByUserId(String u) async => [];
  @override
  Future<List<CoachingInviteEntity>> getByGroupId(String g) async => [];
  @override
  Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeGroupRepo groupRepo;
  late _FakeMemberRepo memberRepo;
  late _FakeInviteRepo inviteRepo;
  late InviteUserToGroup usecase;

  setUp(() {
    groupRepo = _FakeGroupRepo();
    memberRepo = _FakeMemberRepo()
      ..setMember('g1', 'coach', _staffMember);
    inviteRepo = _FakeInviteRepo();
    usecase = InviteUserToGroup(
      groupRepo: groupRepo,
      memberRepo: memberRepo,
      inviteRepo: inviteRepo,
    );
  });

  test('creates invite for valid request', () async {
    final invite = await usecase.call(
      groupId: 'g1',
      callerUserId: 'coach',
      invitedUserId: 'user-1',
      uuidGenerator: () => 'inv-id',
      nowMs: 1000,
    );

    expect(invite.groupId, 'g1');
    expect(invite.invitedUserId, 'user-1');
    expect(invite.status, CoachingInviteStatus.pending);
    expect(inviteRepo.saved, isNotNull);
  });

  test('throws when group not found', () {
    expect(
      () => usecase.call(
        groupId: 'unknown',
        callerUserId: 'coach',
        invitedUserId: 'user-1',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<CoachingGroupNotFound>()),
    );
  });

  test('throws when caller is not staff', () {
    memberRepo.setMember('g1', 'athlete', const CoachingMemberEntity(
      id: 'm-a',
      userId: 'athlete',
      groupId: 'g1',
      displayName: 'A',
      role: CoachingRole.athlete,
      joinedAtMs: 0,
    ));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'athlete',
        invitedUserId: 'user-1',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<InsufficientCoachingRole>()),
    );
  });

  test('throws when user already a member', () {
    memberRepo.setMember('g1', 'user-1', const CoachingMemberEntity(
      id: 'm-u1',
      userId: 'user-1',
      groupId: 'g1',
      displayName: 'User',
      role: CoachingRole.athlete,
      joinedAtMs: 0,
    ));

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'coach',
        invitedUserId: 'user-1',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<AlreadyCoachingMember>()),
    );
  });

  test('throws when pending invite already exists', () {
    inviteRepo.pendingInvite = const CoachingInviteEntity(
      id: 'old',
      groupId: 'g1',
      invitedUserId: 'user-1',
      invitedByUserId: 'coach',
      status: CoachingInviteStatus.pending,
      expiresAtMs: 9999,
      createdAtMs: 0,
    );

    expect(
      () => usecase.call(
        groupId: 'g1',
        callerUserId: 'coach',
        invitedUserId: 'user-1',
        uuidGenerator: () => 'id',
        nowMs: 1000,
      ),
      throwsA(isA<CoachingInviteAlreadyExists>()),
    );
  });
}
