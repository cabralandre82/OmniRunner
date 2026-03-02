import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';

class _FakeRepo implements IChallengeRepo {
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
  Future<ChallengeResultEntity?> getResultByChallengeId(String id) async => null;
}

ChallengeEntity _pending1v1() => ChallengeEntity(
      id: 'ch-1',
      creatorUserId: 'u1',
      status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      participants: const [
        ChallengeParticipantEntity(userId: 'u1', displayName: 'A', status: ParticipantStatus.accepted),
        ChallengeParticipantEntity(userId: 'u2', displayName: 'B', status: ParticipantStatus.accepted),
      ],
      createdAtMs: 0,
    );

void main() {
  late _FakeRepo repo;
  late StartChallenge usecase;

  setUp(() {
    repo = _FakeRepo();
    usecase = StartChallenge(challengeRepo: repo);
  });

  test('starts 1v1 with 2 accepted participants', () async {
    repo.stored = _pending1v1();
    final result = await usecase.call(challengeId: 'ch-1', nowMs: 5000);
    expect(result.status, ChallengeStatus.active);
    expect(result.startsAtMs, 5000);
    expect(result.endsAtMs, 5000 + 86400000);
  });

  test('throws when not pending', () {
    repo.stored = _pending1v1().copyWith(status: ChallengeStatus.active);
    expect(
      () => usecase.call(challengeId: 'ch-1', nowMs: 5000),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });

  test('throws when 1v1 has only 1 accepted', () {
    repo.stored = ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: const [
        ChallengeParticipantEntity(userId: 'u1', displayName: 'A', status: ParticipantStatus.accepted),
        ChallengeParticipantEntity(userId: 'u2', displayName: 'B', status: ParticipantStatus.invited),
      ],
      createdAtMs: 0,
    );
    expect(
      () => usecase.call(challengeId: 'ch-1', nowMs: 5000),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });
}
