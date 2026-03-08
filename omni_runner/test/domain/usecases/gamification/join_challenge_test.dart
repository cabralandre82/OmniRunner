import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';

class _FakeChallengeRepo implements IChallengeRepo {
  ChallengeEntity? stored;
  ChallengeEntity? updatedWith;

  @override
  Future<ChallengeEntity?> getById(String id) async => stored;
  @override
  Future<void> update(ChallengeEntity c) async => updatedWith = c;
  @override
  Future<void> save(ChallengeEntity c) async {}
  @override
  Future<List<ChallengeEntity>> getByUserId(String u) async => [];
  @override
  Future<List<ChallengeEntity>> getByStatus(ChallengeStatus s) async => [];
  @override
  Future<void> deleteById(String id) async {}
  @override
  Future<void> saveResult(ChallengeResultEntity r) async {}
  @override
  Future<ChallengeResultEntity?> getResultByChallengeId(String id) async =>
      null;
}

ChallengeEntity _pendingWithInvitee() => const ChallengeEntity(
      id: 'ch-1',
      creatorUserId: 'creator',
      status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      participants: [
        ChallengeParticipantEntity(
          userId: 'creator',
          displayName: 'Creator',
          status: ParticipantStatus.accepted,
        ),
        ChallengeParticipantEntity(
          userId: 'invitee',
          displayName: 'Invitee',
          status: ParticipantStatus.invited,
        ),
      ],
      createdAtMs: 0,
    );

void main() {
  late _FakeChallengeRepo repo;
  late JoinChallenge usecase;

  setUp(() {
    repo = _FakeChallengeRepo();
    usecase = JoinChallenge(challengeRepo: repo);
  });

  test('accepts an invited participant', () async {
    repo.stored = _pendingWithInvitee();

    final result = await usecase.call(
      challengeId: 'ch-1',
      userId: 'invitee',
      respondedAtMs: 1000,
    );

    final invitee = result.participants.firstWhere((p) => p.userId == 'invitee');
    expect(invitee.status, ParticipantStatus.accepted);
    expect(invitee.respondedAtMs, 1000);
    expect(repo.updatedWith, isNotNull);
  });

  test('throws when challenge not found', () {
    expect(
      () => usecase.call(
        challengeId: 'x',
        userId: 'invitee',
        respondedAtMs: 1000,
      ),
      throwsA(isA<ChallengeNotFound>()),
    );
  });

  test('throws when challenge is not pending', () {
    repo.stored = const ChallengeEntity(
      id: 'ch-1',
      creatorUserId: 'creator',
      status: ChallengeStatus.active,
      type: ChallengeType.oneVsOne,
      rules: ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      participants: [
        ChallengeParticipantEntity(
          userId: 'invitee',
          displayName: 'Invitee',
          status: ParticipantStatus.invited,
        ),
      ],
      createdAtMs: 0,
    );

    expect(
      () => usecase.call(
        challengeId: 'ch-1',
        userId: 'invitee',
        respondedAtMs: 1000,
      ),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });

  test('throws when user is not a participant', () {
    repo.stored = _pendingWithInvitee();

    expect(
      () => usecase.call(
        challengeId: 'ch-1',
        userId: 'unknown',
        respondedAtMs: 1000,
      ),
      throwsA(isA<NotAParticipant>()),
    );
  });

  test('throws when participant already accepted', () {
    repo.stored = _pendingWithInvitee();

    expect(
      () => usecase.call(
        challengeId: 'ch-1',
        userId: 'creator',
        respondedAtMs: 1000,
      ),
      throwsA(isA<AlreadyParticipant>()),
    );
  });
}
