import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/usecases/gamification/challenge_evaluator.dart';

void main() {
  const evaluator = ChallengeEvaluator();

  ChallengeParticipantEntity _p(
    String userId, {
    double progress = 0.0,
    List<String> sessions = const [],
    int? lastSubmittedAtMs,
    ParticipantStatus status = ParticipantStatus.accepted,
  }) =>
      ChallengeParticipantEntity(
        userId: userId,
        displayName: userId,
        status: status,
        progressValue: progress,
        contributingSessionIds: sessions,
        lastSubmittedAtMs: lastSubmittedAtMs,
      );

  ChallengeEntity _challenge({
    ChallengeType type = ChallengeType.oneVsOne,
    ChallengeGoal goal = ChallengeGoal.mostDistance,
    double? target,
    required List<ChallengeParticipantEntity> participants,
  }) =>
      ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: type,
        rules: ChallengeRulesEntity(
          goal: goal,
          target: target,
          windowMs: 604800000,
        ),
        participants: participants,
        createdAtMs: 1000,
      );

  // ── 1v1 DISTANCE (higher wins) ───────────────────────────────

  group('1v1 distance', () {
    test('higher distance wins', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 10000, sessions: ['s1']),
          _p('u2', progress: 8000, sessions: ['s2']),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      expect(active.length, 2);

      final winner = active.firstWhere((r) => r.rank == 1);
      final loser = active.firstWhere((r) => r.rank == 2);
      expect(winner.userId, 'u1');
      expect(winner.outcome, ParticipantOutcome.won);
      expect(winner.coinsEarned, 0);
      expect(loser.userId, 'u2');
      expect(loser.outcome, ParticipantOutcome.lost);
      expect(loser.coinsEarned, 0);
    });

    test('tie broken by earliestFinish', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1',
              progress: 5000,
              sessions: ['s1'],
              lastSubmittedAtMs: 2000),
          _p('u2',
              progress: 5000,
              sessions: ['s2'],
              lastSubmittedAtMs: 1000),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      final winner = active.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u2');
      expect(winner.outcome, ParticipantOutcome.won);
    });

    test('true tie when same value and same timestamp', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1',
              progress: 5000,
              sessions: ['s1'],
              lastSubmittedAtMs: 1000),
          _p('u2',
              progress: 5000,
              sessions: ['s2'],
              lastSubmittedAtMs: 1000),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      expect(active.every((r) => r.rank == 1), isTrue);
      expect(active.every((r) => r.outcome == ParticipantOutcome.tied), isTrue);
      expect(active.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('true tie when same value and both null timestamps', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
          _p('u2', progress: 5000, sessions: ['s2']),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      expect(active.every((r) => r.outcome == ParticipantOutcome.tied), isTrue);
    });
  });

  // ── 1v1 TIME (lower wins — faster completion = better) ──────

  group('1v1 time', () {
    test('lower duration wins (faster runner)', () {
      final results = evaluator.evaluate(_challenge(
        goal: ChallengeGoal.fastestAtDistance,
        participants: [
          _p('u1', progress: 1800000, sessions: ['s1']),
          _p('u2', progress: 1200000, sessions: ['s2']),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      final winner = active.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u2');
      expect(winner.outcome, ParticipantOutcome.won);
      expect(winner.coinsEarned, 0);
    });

    test('time tie broken by earliestFinish', () {
      final results = evaluator.evaluate(_challenge(
        goal: ChallengeGoal.fastestAtDistance,
        participants: [
          _p('u1',
              progress: 1200000,
              sessions: ['s1'],
              lastSubmittedAtMs: 5000),
          _p('u2',
              progress: 1200000,
              sessions: ['s2'],
              lastSubmittedAtMs: 3000),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      final winner = active.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u2');
    });
  });

  // ── 1v1 PACE (lower wins) ────────────────────────────────────

  group('1v1 pace', () {
    test('lower pace wins', () {
      final results = evaluator.evaluate(_challenge(
        goal: ChallengeGoal.bestPaceAtDistance,
        participants: [
          _p('u1', progress: 300, sessions: ['s1']),
          _p('u2', progress: 270, sessions: ['s2']),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      final winner = active.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u2');
      expect(winner.outcome, ParticipantOutcome.won);
    });
  });

  // ── 1v1 EDGE CASES ───────────────────────────────────────────

  group('1v1 edge cases', () {
    test('no participants returns empty', () {
      final results = evaluator.evaluate(_challenge(participants: []));
      expect(results, isEmpty);
    });

    test('single participant auto-wins', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
        ],
      ));

      expect(results.length, 1);
      expect(results[0].outcome, ParticipantOutcome.won);
      expect(results[0].coinsEarned, 0);
    });

    test('nobody submitted anything: both DNF with 0 coins (free)', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 0),
          _p('u2', progress: 0),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('nobody submitted with stake: both DNF, coins refunded', () {
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: ChallengeType.oneVsOne,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.mostDistance,
          windowMs: 604800000,
          entryFeeCoins: 50,
        ),
        participants: [
          _p('u1', progress: 0),
          _p('u2', progress: 0),
        ],
        createdAtMs: 1000,
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 50), isTrue);
    });

    test('one runs other does not: runner wins (stake)', () {
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: ChallengeType.oneVsOne,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.mostDistance,
          windowMs: 604800000,
          entryFeeCoins: 50,
        ),
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
          _p('u2', progress: 0),
        ],
        createdAtMs: 1000,
      ));

      final winner = results.firstWhere(
        (r) => r.outcome == ParticipantOutcome.won,
      );
      final dnf = results.firstWhere(
        (r) => r.outcome == ParticipantOutcome.didNotFinish,
      );
      expect(winner.userId, 'u1');
      expect(winner.coinsEarned, 100);
      expect(dnf.userId, 'u2');
      expect(dnf.coinsEarned, 0);
    });

    test('one runs other does not: runner wins (free, 0 coins)', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
          _p('u2', progress: 0),
        ],
      ));

      final winner = results.firstWhere(
        (r) => r.outcome == ParticipantOutcome.won,
      );
      final dnf = results.firstWhere(
        (r) => r.outcome == ParticipantOutcome.didNotFinish,
      );
      expect(winner.userId, 'u1');
      expect(winner.coinsEarned, 0);
      expect(dnf.userId, 'u2');
      expect(dnf.coinsEarned, 0);
    });

    test('non-accepted participants appear as DNF', () {
      final results = evaluator.evaluate(_challenge(
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
          _p('u2', status: ParticipantStatus.declined),
        ],
      ));

      final dnf = results.where(
        (r) => r.outcome == ParticipantOutcome.didNotFinish,
      );
      expect(dnf.length, 1);
      expect(dnf.first.userId, 'u2');
      expect(dnf.first.coinsEarned, 0);
    });
  });

  // ── GROUP (cooperative — group wins/loses as a unit) ──────────

  group('group distance (cooperative via collectiveDistance)', () {
    test('collective sum meets target: 0 coins (free)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.collectiveDistance,
        target: 30000,
        participants: [
          _p('u1', progress: 15000, sessions: ['s1']),
          _p('u2', progress: 12000, sessions: ['s2']),
          _p('u3', progress: 8000, sessions: ['s3']),
        ],
      ));

      expect(results.length, 3);
      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('collective sum does not meet target: 0 coins', () {
      // target = 50000. sum = 15000+12000+8000 = 35000 < 50000 → not met
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.collectiveDistance,
        target: 50000,
        participants: [
          _p('u1', progress: 15000, sessions: ['s1']),
          _p('u2', progress: 12000, sessions: ['s2']),
          _p('u3', progress: 8000, sessions: ['s3']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.participated),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('non-runner shares result when group meets target (free, 0 coins)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.collectiveDistance,
        target: 10000,
        participants: [
          _p('u1', progress: 8000, sessions: ['s1']),
          _p('u2', progress: 5000, sessions: ['s2']),
          _p('u3', progress: 0),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('group with stake: pool split equally among all', () {
      // Pool = 20 * 3 = 60. target met → 60/3 = 20 each
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: ChallengeType.group,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.collectiveDistance,
          target: 10000,
          windowMs: 604800000,
          entryFeeCoins: 20,
        ),
        participants: [
          _p('u1', progress: 6000, sessions: ['s1']),
          _p('u2', progress: 5000, sessions: ['s2']),
          _p('u3', progress: 0),
        ],
        createdAtMs: 1000,
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 20), isTrue);
    });

    test('no target: group succeeds if anyone ran (free, 0 coins)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.collectiveDistance,
        participants: [
          _p('u1', progress: 3000, sessions: ['s1']),
          _p('u2', progress: 0),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('nobody ran with stake: all DNF, refund', () {
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: ChallengeType.group,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.collectiveDistance,
          target: 5000,
          windowMs: 604800000,
          entryFeeCoins: 20,
        ),
        participants: [
          _p('u1', progress: 0),
          _p('u2', progress: 0),
          _p('u3', progress: 0),
        ],
        createdAtMs: 1000,
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 20), isTrue);
    });

    test('nobody ran free: all DNF, 0 coins', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.collectiveDistance,
        target: 5000,
        participants: [
          _p('u1', progress: 0),
          _p('u2', progress: 0),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });
  });

  // ── GROUP PACE (competitive — lower pace wins) ────────────────

  group('group pace (competitive)', () {
    test('lower pace wins in competitive group', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.bestPaceAtDistance,
        target: 300,
        participants: [
          _p('u1', progress: 270, sessions: ['s1']),
          _p('u2', progress: 290, sessions: ['s2']),
        ],
      ));

      final winner = results.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u1');
      expect(winner.outcome, ParticipantOutcome.won);
    });

    test('slower runner is ranked lower', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.bestPaceAtDistance,
        target: 300,
        participants: [
          _p('u1', progress: 270, sessions: ['s1']),
          _p('u2', progress: 350, sessions: ['s2']),
        ],
      ));

      final second = results.firstWhere((r) => r.userId == 'u2');
      expect(second.rank, 2);
      expect(second.outcome, ParticipantOutcome.participated);
      expect(second.coinsEarned, 0);
    });
  });

  // ── GROUP TIME (competitive — lower time wins) ────────────────

  group('group time (competitive)', () {
    test('fastest runner wins in competitive group', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.fastestAtDistance,
        participants: [
          _p('u1', progress: 1500000, sessions: ['s1']),
          _p('u2', progress: 2000000, sessions: ['s2']),
          _p('u3', progress: 1200000, sessions: ['s3']),
        ],
      ));

      final winner = results.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u3');
      expect(winner.outcome, ParticipantOutcome.won);
    });

    test('slower runners are ranked by time ascending', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        goal: ChallengeGoal.fastestAtDistance,
        participants: [
          _p('u1', progress: 1500000, sessions: ['s1']),
          _p('u2', progress: 1200000, sessions: ['s2']),
        ],
      ));

      final first = results.firstWhere((r) => r.rank == 1);
      final second = results.firstWhere((r) => r.rank == 2);
      expect(first.userId, 'u2');
      expect(second.userId, 'u1');
      expect(second.outcome, ParticipantOutcome.participated);
    });
  });

  // ── TEAM VS TEAM ─────────────────────────────────────────────

  ChallengeParticipantEntity _tp(
    String userId, {
    required String team,
    double progress = 0.0,
    List<String> sessions = const [],
    int? lastSubmittedAtMs,
  }) =>
      ChallengeParticipantEntity(
        userId: userId,
        displayName: userId,
        status: ParticipantStatus.accepted,
        progressValue: progress,
        contributingSessionIds: sessions,
        lastSubmittedAtMs: lastSubmittedAtMs,
        team: team,
      );

  group('team mostDistance', () {
    test('team with higher total distance wins', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.team,
        goal: ChallengeGoal.mostDistance,
        participants: [
          _tp('a1', team: 'A', progress: 5000, sessions: ['s1']),
          _tp('a2', team: 'A', progress: 6000, sessions: ['s2']),
          _tp('b1', team: 'B', progress: 4000, sessions: ['s3']),
          _tp('b2', team: 'B', progress: 3000, sessions: ['s4']),
        ],
      ));

      final teamAResults = results.where((r) => r.userId.startsWith('a'));
      final teamBResults = results.where((r) => r.userId.startsWith('b'));
      expect(teamAResults.every((r) => r.outcome == ParticipantOutcome.won), isTrue);
      expect(teamBResults.every((r) => r.outcome == ParticipantOutcome.lost), isTrue);
    });

    test('team with staked coins — winner gets double', () {
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'a1',
        status: ChallengeStatus.active,
        type: ChallengeType.team,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.mostDistance,
          windowMs: 604800000,
          entryFeeCoins: 100,
        ),
        participants: [
          _tp('a1', team: 'A', progress: 8000, sessions: ['s1']),
          _tp('b1', team: 'B', progress: 3000, sessions: ['s2']),
        ],
        createdAtMs: 1000,
      ));

      final winner = results.firstWhere((r) => r.userId == 'a1');
      final loser = results.firstWhere((r) => r.userId == 'b1');
      expect(winner.outcome, ParticipantOutcome.won);
      expect(winner.coinsEarned, 200);
      expect(loser.outcome, ParticipantOutcome.lost);
      expect(loser.coinsEarned, 0);
    });
  });

  group('team fastestAtDistance', () {
    test('last runner determines team time — faster team wins', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.team,
        goal: ChallengeGoal.fastestAtDistance,
        target: 10000,
        participants: [
          _tp('a1', team: 'A', progress: 3000, sessions: ['s1']),
          _tp('a2', team: 'A', progress: 3500, sessions: ['s2']),
          _tp('b1', team: 'B', progress: 3200, sessions: ['s3']),
          _tp('b2', team: 'B', progress: 4000, sessions: ['s4']),
        ],
      ));

      final teamAResults = results.where((r) => r.userId.startsWith('a'));
      final teamBResults = results.where((r) => r.userId.startsWith('b'));
      expect(teamAResults.every((r) => r.outcome == ParticipantOutcome.won), isTrue);
      expect(teamBResults.every((r) => r.outcome == ParticipantOutcome.lost), isTrue);
    });

    test('incomplete team (missing runner) loses', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.team,
        goal: ChallengeGoal.fastestAtDistance,
        target: 10000,
        participants: [
          _tp('a1', team: 'A', progress: 5000, sessions: ['s1']),
          _tp('a2', team: 'A', progress: 0, sessions: []),
          _tp('b1', team: 'B', progress: 4000, sessions: ['s3']),
          _tp('b2', team: 'B', progress: 3800, sessions: ['s4']),
        ],
      ));

      final teamBResults = results.where((r) => r.userId.startsWith('b'));
      expect(teamBResults.every((r) => r.outcome == ParticipantOutcome.won), isTrue);
    });
  });

  group('team bestPaceAtDistance', () {
    test('average pace determines winner — lower is better', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.team,
        goal: ChallengeGoal.bestPaceAtDistance,
        target: 5000,
        participants: [
          _tp('a1', team: 'A', progress: 300, sessions: ['s1']),
          _tp('a2', team: 'A', progress: 320, sessions: ['s2']),
          _tp('b1', team: 'B', progress: 290, sessions: ['s3']),
          _tp('b2', team: 'B', progress: 350, sessions: ['s4']),
        ],
      ));

      final teamAResults = results.where((r) => r.userId.startsWith('a'));
      expect(teamAResults.every((r) => r.outcome == ParticipantOutcome.won), isTrue);
    });
  });

  group('team nobody ran', () {
    test('all DNF — refund stakes', () {
      final results = evaluator.evaluate(ChallengeEntity(
        id: 'c1',
        creatorUserId: 'a1',
        status: ChallengeStatus.active,
        type: ChallengeType.team,
        rules: const ChallengeRulesEntity(
          goal: ChallengeGoal.mostDistance,
          windowMs: 604800000,
          entryFeeCoins: 50,
        ),
        participants: [
          _tp('a1', team: 'A'),
          _tp('b1', team: 'B'),
        ],
        createdAtMs: 1000,
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish), isTrue);
      expect(results.every((r) => r.coinsEarned == 50), isTrue);
    });
  });

  // ── MIXED STATUS ──────────────────────────────────────────────

  group('mixed participant statuses', () {
    test('invited + withdrawn appear as DNF', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        participants: [
          _p('u1', progress: 5000, sessions: ['s1']),
          _p('u2', status: ParticipantStatus.invited),
          _p('u3', status: ParticipantStatus.withdrawn),
        ],
      ));

      final dnf = results.where(
        (r) => r.outcome == ParticipantOutcome.didNotFinish,
      );
      expect(dnf.length, 2);
      expect(dnf.map((r) => r.userId).toSet(), {'u2', 'u3'});
    });
  });
}
