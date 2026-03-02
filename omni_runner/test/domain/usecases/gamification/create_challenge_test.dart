import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';

class _FakeChallengeRepo implements IChallengeRepo {
  ChallengeEntity? saved;

  @override
  Future<void> save(ChallengeEntity c) async => saved = c;
  @override
  Future<ChallengeEntity?> getById(String id) async => null;
  @override
  Future<void> update(ChallengeEntity c) async {}
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

void main() {
  late _FakeChallengeRepo repo;
  late CreateChallenge usecase;

  setUp(() {
    repo = _FakeChallengeRepo();
    usecase = CreateChallenge(challengeRepo: repo);
  });

  test('creates pending challenge with creator as first participant', () async {
    final challenge = await usecase.call(
      id: 'ch-1',
      creatorUserId: 'u1',
      creatorDisplayName: 'Alice',
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
      ),
      createdAtMs: 1000,
      title: 'Test Challenge',
    );

    expect(challenge.id, 'ch-1');
    expect(challenge.status, ChallengeStatus.pending);
    expect(challenge.participants, hasLength(1));
    expect(challenge.participants.first.userId, 'u1');
    expect(
      challenge.participants.first.status,
      ParticipantStatus.accepted,
    );
    expect(challenge.title, 'Test Challenge');
    expect(repo.saved, isNotNull);
  });

  test('sets accept deadline when acceptWindowMin is specified', () async {
    final challenge = await usecase.call(
      id: 'ch-2',
      creatorUserId: 'u1',
      creatorDisplayName: 'Alice',
      type: ChallengeType.group,
      rules: const ChallengeRulesEntity(
        goal: ChallengeGoal.mostDistance,
        windowMs: 86400000,
        acceptWindowMin: 60,
      ),
      createdAtMs: 1000,
    );

    expect(challenge.acceptDeadlineMs, 1000 + 60 * 60 * 1000);
  });
}
