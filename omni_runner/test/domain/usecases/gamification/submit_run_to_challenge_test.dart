import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/submit_run_to_challenge.dart';

class _FakeRepo implements IChallengeRepo {
  ChallengeEntity? stored;
  ChallengeEntity? updatedWith;
  @override Future<ChallengeEntity?> getById(String id) async => stored;
  @override Future<void> update(ChallengeEntity c) async => updatedWith = c;
  @override Future<void> save(ChallengeEntity c) async {}
  @override Future<List<ChallengeEntity>> getByUserId(String u) async => [];
  @override Future<List<ChallengeEntity>> getByStatus(ChallengeStatus s) async => [];
  @override Future<void> deleteById(String id) async {}
  @override Future<void> saveResult(ChallengeResultEntity r) async {}
  @override Future<ChallengeResultEntity?> getResultByChallengeId(String id) async => null;
}

final _activeChallenge = ChallengeEntity(
  id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.active,
  type: ChallengeType.oneVsOne,
  rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
  participants: const [
    ChallengeParticipantEntity(userId: 'u1', displayName: 'A', status: ParticipantStatus.accepted),
    ChallengeParticipantEntity(userId: 'u2', displayName: 'B', status: ParticipantStatus.accepted),
  ],
  createdAtMs: 0, startsAtMs: 0, endsAtMs: 86400000,
);

final _session = WorkoutSessionEntity(
  id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
  startTimeMs: 1000, route: const [], isVerified: true, totalDistanceM: 5000,
);

void main() {
  late _FakeRepo repo;
  late SubmitRunToChallenge usecase;

  setUp(() {
    repo = _FakeRepo()..stored = _activeChallenge;
    usecase = SubmitRunToChallenge(challengeRepo: repo);
  });

  test('submits run and updates progress', () async {
    final result = await usecase.call(
      challengeId: 'ch-1', userId: 'u1', session: _session, metricValue: 5000,
    );
    final p = result.participants.firstWhere((p) => p.userId == 'u1');
    expect(p.progressValue, 5000);
    expect(p.contributingSessionIds, contains('ses-1'));
  });

  test('throws when challenge not active', () {
    repo.stored = _activeChallenge.copyWith(status: ChallengeStatus.pending);
    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u1', session: _session, metricValue: 5000),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });

  test('throws when session unverified', () {
    final unverified = WorkoutSessionEntity(
      id: 'ses-2', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: const [], isVerified: false, totalDistanceM: 5000,
    );
    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u1', session: unverified, metricValue: 5000),
      throwsA(isA<UnverifiedSession>()),
    );
  });

  test('throws when session below min distance', () {
    final short = WorkoutSessionEntity(
      id: 'ses-3', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: const [], isVerified: true, totalDistanceM: 500,
    );
    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u1', session: short, metricValue: 500),
      throwsA(isA<SessionBelowMinimum>()),
    );
  });

  test('throws on duplicate session', () async {
    // Submit once
    await usecase.call(challengeId: 'ch-1', userId: 'u1', session: _session, metricValue: 5000);
    // Update stored to reflect the submitted state
    repo.stored = repo.updatedWith;
    expect(
      () => usecase.call(challengeId: 'ch-1', userId: 'u1', session: _session, metricValue: 5000),
      throwsA(isA<SessionAlreadySubmitted>()),
    );
  });
}
