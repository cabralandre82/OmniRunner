import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/invite_participants.dart';

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

ChallengeEntity _pending() => ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.pending,
      type: ChallengeType.group,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: const [
        ChallengeParticipantEntity(userId: 'u1', displayName: 'Creator', status: ParticipantStatus.accepted),
      ],
      createdAtMs: 0,
    );

void main() {
  late _FakeRepo repo;
  late InviteParticipants usecase;

  setUp(() {
    repo = _FakeRepo();
    usecase = InviteParticipants(challengeRepo: repo);
  });

  test('adds invitees', () async {
    repo.stored = _pending();
    final result = await usecase.call(
      challengeId: 'ch-1',
      invitees: [(userId: 'u2', displayName: 'Bob')],
    );
    expect(result.participants, hasLength(2));
    expect(result.participants.last.userId, 'u2');
  });

  test('throws on duplicate participant', () {
    repo.stored = _pending();
    expect(
      () => usecase.call(
        challengeId: 'ch-1',
        invitees: [(userId: 'u1', displayName: 'Dup')],
      ),
      throwsA(isA<AlreadyParticipant>()),
    );
  });

  test('throws when challenge full', () {
    final participants = List.generate(50, (i) =>
      ChallengeParticipantEntity(userId: 'p$i', displayName: 'P$i', status: ParticipantStatus.invited),
    );
    repo.stored = ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.pending,
      type: ChallengeType.group,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: participants, createdAtMs: 0,
    );
    expect(
      () => usecase.call(challengeId: 'ch-1', invitees: [(userId: 'new', displayName: 'New')]),
      throwsA(isA<ChallengeFull>()),
    );
  });
}
