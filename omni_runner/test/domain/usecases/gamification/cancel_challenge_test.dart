import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';

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

ChallengeEntity _pendingChallenge({String creator = 'u1'}) => ChallengeEntity(
      id: 'ch-1',
      creatorUserId: creator,
      status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      participants: [
        ChallengeParticipantEntity(
          userId: creator,
          displayName: creator,
          status: ParticipantStatus.accepted,
        ),
      ],
      createdAtMs: 0,
    );

void main() {
  late _FakeChallengeRepo repo;
  late CancelChallenge usecase;

  setUp(() {
    repo = _FakeChallengeRepo();
    usecase = CancelChallenge(challengeRepo: repo);
  });

  test('cancels pending challenge by creator', () async {
    repo.stored = _pendingChallenge();

    await usecase.call(challengeId: 'ch-1', userId: 'u1');

    expect(repo.updatedWith!.status, ChallengeStatus.cancelled);
  });

  test('throws when challenge not found', () {
    expect(
      () => usecase.call(challengeId: 'x', userId: 'u1'),
      throwsA(isA<ChallengeNotFound>()),
    );
  });

  test('throws when challenge is not pending', () {
    repo.stored = ChallengeEntity(
      id: 'ch-1',
      creatorUserId: 'u1',
      status: ChallengeStatus.active,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      participants: const [],
      createdAtMs: 0,
    );

    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u1'),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });

  test('throws when caller is not the creator', () {
    repo.stored = _pendingChallenge(creator: 'u1');

    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u2'),
      throwsA(isA<NotChallengeCreator>()),
    );
  });
}
