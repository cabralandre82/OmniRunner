import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/post_session_challenge_dispatcher.dart';
import 'package:omni_runner/domain/usecases/gamification/submit_run_to_challenge.dart';

class _FakeRepo implements IChallengeRepo {
  List<ChallengeEntity> userChallenges = [];
  final Map<String, ChallengeEntity> _byId = {};

  void addChallenge(ChallengeEntity c) {
    userChallenges.add(c);
    _byId[c.id] = c;
  }

  @override Future<ChallengeEntity?> getById(String id) async => _byId[id];
  @override Future<void> update(ChallengeEntity c) async => _byId[c.id] = c;
  @override Future<List<ChallengeEntity>> getByUserId(String u) async => userChallenges;
  @override Future<void> save(ChallengeEntity c) async {}
  @override Future<List<ChallengeEntity>> getByStatus(ChallengeStatus s) async => [];
  @override Future<void> deleteById(String id) async {}
  @override Future<void> saveResult(ChallengeResultEntity r) async {}
  @override Future<ChallengeResultEntity?> getResultByChallengeId(String id) async => null;
}

void main() {
  late _FakeRepo repo;
  late PostSessionChallengeDispatcher dispatcher;

  final session = WorkoutSessionEntity(
    id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
    startTimeMs: 100, route: const [], isVerified: true, totalDistanceM: 5000,
  );

  setUp(() {
    repo = _FakeRepo();
    final submitRun = SubmitRunToChallenge(challengeRepo: repo);
    dispatcher = PostSessionChallengeDispatcher(challengeRepo: repo, submitRun: submitRun);
  });

  test('returns empty when no active challenges', () async {
    final bindings = await dispatcher.call(
      session: session, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );
    expect(bindings, isEmpty);
  });

  test('returns empty when session has no userId', () async {
    final noUser = WorkoutSessionEntity(
      id: 'ses-2', status: WorkoutStatus.completed,
      startTimeMs: 0, route: const [], isVerified: true,
    );
    final bindings = await dispatcher.call(
      session: noUser, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );
    expect(bindings, isEmpty);
  });

  test('dispatches to active challenge', () async {
    repo.addChallenge(ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.active,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: const [
        ChallengeParticipantEntity(userId: 'u1', displayName: 'A', status: ParticipantStatus.accepted),
        ChallengeParticipantEntity(userId: 'u2', displayName: 'B', status: ParticipantStatus.accepted),
      ],
      createdAtMs: 0, startsAtMs: 0, endsAtMs: 86400000,
    ));

    final bindings = await dispatcher.call(
      session: session, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );
    expect(bindings, hasLength(1));
  });
}
