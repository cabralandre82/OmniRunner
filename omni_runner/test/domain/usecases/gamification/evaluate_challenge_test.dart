import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';

class _FakeRepo implements IChallengeRepo {
  ChallengeEntity? stored;
  ChallengeEntity? updatedWith;
  ChallengeResultEntity? savedResult;
  @override Future<ChallengeEntity?> getById(String id) async => stored;
  @override Future<void> update(ChallengeEntity c) async => updatedWith = c;
  @override Future<void> saveResult(ChallengeResultEntity r) async => savedResult = r;
  @override Future<void> save(ChallengeEntity c) async {}
  @override Future<List<ChallengeEntity>> getByUserId(String u) async => [];
  @override Future<List<ChallengeEntity>> getByStatus(ChallengeStatus s) async => [];
  @override Future<void> deleteById(String id) async {}
  @override Future<ChallengeResultEntity?> getResultByChallengeId(String id) async => null;
}

const _active = ChallengeEntity(
  id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.active,
  type: ChallengeType.oneVsOne,
  rules: ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000, entryFeeCoins: 10),
  participants: [
    ChallengeParticipantEntity(userId: 'u1', displayName: 'A', status: ParticipantStatus.accepted, progressValue: 8000),
    ChallengeParticipantEntity(userId: 'u2', displayName: 'B', status: ParticipantStatus.accepted, progressValue: 5000),
  ],
  createdAtMs: 0, startsAtMs: 0, endsAtMs: 86400000,
);

void main() {
  late _FakeRepo repo;
  late EvaluateChallenge usecase;

  setUp(() {
    repo = _FakeRepo()..stored = _active;
    usecase = EvaluateChallenge(challengeRepo: repo);
  });

  test('evaluates active challenge, transitions to completing', () async {
    final result = await usecase.call(challengeId: 'ch-1', nowMs: 100000);
    expect(repo.updatedWith!.status, ChallengeStatus.completing);
    expect(result.challengeId, 'ch-1');
    expect(repo.savedResult, isNotNull);
  });

  test('throws when challenge not active', () {
    repo.stored = _active.copyWith(status: ChallengeStatus.pending);
    expect(
      () => usecase.call(challengeId: 'ch-1', nowMs: 100000),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });

  test('throws when challenge not found', () {
    repo.stored = null;
    expect(
      () => usecase.call(challengeId: 'x', nowMs: 100000),
      throwsA(isA<ChallengeNotFound>()),
    );
  });
}
