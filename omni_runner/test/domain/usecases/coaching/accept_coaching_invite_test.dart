import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/accept_coaching_invite.dart';

class _FakeInviteRepo implements ICoachingInviteRepo {
  CoachingInviteEntity? stored;
  CoachingInviteEntity? updatedWith;

  @override
  Future<CoachingInviteEntity?> getById(String id) async => stored;
  @override
  Future<void> save(CoachingInviteEntity invite) async => stored = invite;
  @override
  Future<void> update(CoachingInviteEntity invite) async =>
      updatedWith = invite;
  @override
  Future<CoachingInviteEntity?> findPending(String g, String u) async => null;
  @override
  Future<List<CoachingInviteEntity>> getPendingByUserId(String u) async => [];
  @override
  Future<List<CoachingInviteEntity>> getByGroupId(String g) async => [];
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
  late _FakeInviteRepo inviteRepo;
  late _FakeMemberRepo memberRepo;
  late AcceptCoachingInvite usecase;

  CoachingInviteEntity makePendingInvite({
    String id = 'inv-1',
    String groupId = 'g1',
    String invitedUserId = 'user-1',
    int expiresAtMs = 999999,
  }) =>
      CoachingInviteEntity(
        id: id,
        groupId: groupId,
        invitedUserId: invitedUserId,
        invitedByUserId: 'coach',
        status: CoachingInviteStatus.pending,
        expiresAtMs: expiresAtMs,
        createdAtMs: 100,
      );

  setUp(() {
    inviteRepo = _FakeInviteRepo();
    memberRepo = _FakeMemberRepo();
    usecase = AcceptCoachingInvite(
      inviteRepo: inviteRepo,
      memberRepo: memberRepo,
    );
  });

  test('accepts a valid pending invite', () async {
    inviteRepo.stored = makePendingInvite();

    final member = await usecase.call(
      inviteId: 'inv-1',
      acceptingUserId: 'user-1',
      displayName: 'João',
      uuidGenerator: () => 'member-id',
      nowMs: 500,
    );

    expect(member.role, CoachingRole.athlete);
    expect(member.userId, 'user-1');
    expect(member.groupId, 'g1');
    expect(memberRepo.saved, isNotNull);
    expect(inviteRepo.updatedWith!.status, CoachingInviteStatus.accepted);
  });

  test('throws when invite not found', () async {
    inviteRepo.stored = null;

    expect(
      () => usecase.call(
        inviteId: 'inv-1',
        acceptingUserId: 'user-1',
        displayName: 'João',
        uuidGenerator: () => 'id',
        nowMs: 500,
      ),
      throwsA(isA<CoachingInviteNotFound>()),
    );
  });

  test('throws when invite is not pending', () async {
    inviteRepo.stored = const CoachingInviteEntity(
      id: 'inv-1',
      groupId: 'g1',
      invitedUserId: 'user-1',
      invitedByUserId: 'coach',
      status: CoachingInviteStatus.accepted,
      expiresAtMs: 999999,
      createdAtMs: 100,
    );

    expect(
      () => usecase.call(
        inviteId: 'inv-1',
        acceptingUserId: 'user-1',
        displayName: 'João',
        uuidGenerator: () => 'id',
        nowMs: 500,
      ),
      throwsA(isA<InvalidCoachingInviteStatus>()),
    );
  });

  test('throws when invite expired', () async {
    inviteRepo.stored = makePendingInvite(expiresAtMs: 100);

    expect(
      () => usecase.call(
        inviteId: 'inv-1',
        acceptingUserId: 'user-1',
        displayName: 'João',
        uuidGenerator: () => 'id',
        nowMs: 500,
      ),
      throwsA(isA<CoachingInviteExpired>()),
    );
  });

  test('throws when accepting user is not the invited user', () async {
    inviteRepo.stored = makePendingInvite(invitedUserId: 'other-user');

    expect(
      () => usecase.call(
        inviteId: 'inv-1',
        acceptingUserId: 'user-1',
        displayName: 'João',
        uuidGenerator: () => 'id',
        nowMs: 500,
      ),
      throwsA(isA<InvalidCoachingInviteStatus>()),
    );
  });
}
