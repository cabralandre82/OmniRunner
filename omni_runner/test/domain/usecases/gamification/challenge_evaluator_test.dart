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
    ChallengeMetric metric = ChallengeMetric.distance,
    double? target,
    required List<ChallengeParticipantEntity> participants,
  }) =>
      ChallengeEntity(
        id: 'c1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: type,
        rules: ChallengeRulesEntity(
          metric: metric,
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

  // ── 1v1 TIME (higher wins — more running time = better) ─────

  group('1v1 time', () {
    test('higher duration wins', () {
      final results = evaluator.evaluate(_challenge(
        metric: ChallengeMetric.time,
        participants: [
          _p('u1', progress: 1800000, sessions: ['s1']),
          _p('u2', progress: 1200000, sessions: ['s2']),
        ],
      ));

      final active = results.where(
        (r) => r.outcome != ParticipantOutcome.didNotFinish,
      );
      final winner = active.firstWhere((r) => r.rank == 1);
      expect(winner.userId, 'u1');
      expect(winner.outcome, ParticipantOutcome.won);
      expect(winner.coinsEarned, 0);
    });

    test('time tie broken by earliestFinish', () {
      final results = evaluator.evaluate(_challenge(
        metric: ChallengeMetric.time,
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
        metric: ChallengeMetric.pace,
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
          metric: ChallengeMetric.distance,
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
          metric: ChallengeMetric.distance,
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

  group('group distance (cooperative)', () {
    test('collective sum meets target: 0 coins (free)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
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
          metric: ChallengeMetric.distance,
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
          metric: ChallengeMetric.distance,
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

  // ── GROUP PACE (cooperative — avg of runners ≤ target) ────────

  group('group pace (cooperative)', () {
    test('avg pace meets target (free, 0 coins)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        metric: ChallengeMetric.pace,
        target: 300,
        participants: [
          _p('u1', progress: 270, sessions: ['s1']),
          _p('u2', progress: 290, sessions: ['s2']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('avg pace too slow: no reward', () {
      // avg = (270+350)/2 = 310 > 300 → not met
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        metric: ChallengeMetric.pace,
        target: 300,
        participants: [
          _p('u1', progress: 270, sessions: ['s1']),
          _p('u2', progress: 350, sessions: ['s2']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.participated),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });
  });

  // ── GROUP TIME (cooperative — sum of runners ≥ target) ────────

  group('group time (cooperative)', () {
    test('collective time meets target (free, 0 coins)', () {
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        metric: ChallengeMetric.time,
        target: 4000000,
        participants: [
          _p('u1', progress: 1500000, sessions: ['s1']),
          _p('u2', progress: 2000000, sessions: ['s2']),
          _p('u3', progress: 1200000, sessions: ['s3']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.completedTarget),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('collective time not enough: no reward', () {
      // sum = 1500000+1200000 = 2700000 < 4000000 → not met
      final results = evaluator.evaluate(_challenge(
        type: ChallengeType.group,
        metric: ChallengeMetric.time,
        target: 4000000,
        participants: [
          _p('u1', progress: 1500000, sessions: ['s1']),
          _p('u2', progress: 1200000, sessions: ['s2']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.participated),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 0), isTrue);
    });
  });

  // ── TEAM VS TEAM ─────────────────────────────────────────────

  ChallengeParticipantEntity _tp(
    String userId, {
    required String team,
    double progress = 0.0,
    List<String> sessions = const [],
  }) =>
      ChallengeParticipantEntity(
        userId: userId,
        displayName: userId,
        status: ParticipantStatus.accepted,
        progressValue: progress,
        contributingSessionIds: sessions,
        team: team,
      );

  ChallengeEntity _teamChallenge({
    ChallengeMetric metric = ChallengeMetric.distance,
    int entryFeeCoins = 0,
    required List<ChallengeParticipantEntity> participants,
  }) =>
      ChallengeEntity(
        id: 'tc1',
        creatorUserId: 'u1',
        status: ChallengeStatus.active,
        type: ChallengeType.teamVsTeam,
        rules: ChallengeRulesEntity(
          metric: metric,
          windowMs: 604800000,
          entryFeeCoins: entryFeeCoins,
        ),
        participants: participants,
        createdAtMs: 1000,
        teamAGroupId: 'gA',
        teamBGroupId: 'gB',
      );

  group('team vs team distance', () {
    test('team with higher total wins', () {
      final results = evaluator.evaluate(_teamChallenge(
        participants: [
          _tp('u1', team: 'A', progress: 10000, sessions: ['s1']),
          _tp('u2', team: 'A', progress: 8000, sessions: ['s2']),
          _tp('u3', team: 'B', progress: 7000, sessions: ['s3']),
          _tp('u4', team: 'B', progress: 5000, sessions: ['s4']),
        ],
      ));

      final winners = results.where((r) => r.outcome == ParticipantOutcome.won);
      final losers = results.where((r) => r.outcome == ParticipantOutcome.lost);

      expect(winners.length, 2);
      expect(losers.length, 2);
      expect(winners.every((r) => r.userId == 'u1' || r.userId == 'u2'), isTrue);
      expect(losers.every((r) => r.userId == 'u3' || r.userId == 'u4'), isTrue);
    });

    test('tied teams produce tie outcome', () {
      final results = evaluator.evaluate(_teamChallenge(
        participants: [
          _tp('u1', team: 'A', progress: 10000, sessions: ['s1']),
          _tp('u2', team: 'B', progress: 10000, sessions: ['s2']),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.tied), isTrue);
    });

    test('pool is split among winning team', () {
      final results = evaluator.evaluate(_teamChallenge(
        entryFeeCoins: 10,
        participants: [
          _tp('u1', team: 'A', progress: 10000, sessions: ['s1']),
          _tp('u2', team: 'A', progress: 8000, sessions: ['s2']),
          _tp('u3', team: 'B', progress: 5000, sessions: ['s3']),
          _tp('u4', team: 'B', progress: 3000, sessions: ['s4']),
        ],
      ));

      // Pool = 10 * 4 = 40. Winners (2 people) get 40/2 = 20 each.
      final winners = results.where((r) => r.outcome == ParticipantOutcome.won);
      expect(winners.every((r) => r.coinsEarned == 20), isTrue);

      // Losers get 0 from pool
      final losers = results.where((r) => r.outcome == ParticipantOutcome.lost);
      expect(losers.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('tie splits pool across all', () {
      final results = evaluator.evaluate(_teamChallenge(
        entryFeeCoins: 10,
        participants: [
          _tp('u1', team: 'A', progress: 5000, sessions: ['s1']),
          _tp('u2', team: 'B', progress: 5000, sessions: ['s2']),
        ],
      ));

      // Pool = 10 * 2 = 20. All 2 get 20/2 = 10 each.
      expect(results.every((r) => r.coinsEarned == 10), isTrue);
    });

    test('non-runner on winning team still shares pool', () {
      final results = evaluator.evaluate(_teamChallenge(
        entryFeeCoins: 10,
        participants: [
          _tp('u1', team: 'A', progress: 10000, sessions: ['s1']),
          _tp('u2', team: 'A', progress: 0),
          _tp('u3', team: 'B', progress: 5000, sessions: ['s3']),
          _tp('u4', team: 'B', progress: 3000, sessions: ['s4']),
        ],
      ));

      // Pool = 10 * 4 = 40. Team A wins (2 members) → 40/2 = 20 each.
      final u1 = results.firstWhere((r) => r.userId == 'u1');
      expect(u1.outcome, ParticipantOutcome.won);
      expect(u1.coinsEarned, 20);

      final u2 = results.firstWhere((r) => r.userId == 'u2');
      expect(u2.outcome, ParticipantOutcome.won);
      expect(u2.coinsEarned, 20);

      final losers = results.where((r) => r.outcome == ParticipantOutcome.lost);
      expect(losers.every((r) => r.coinsEarned == 0), isTrue);
    });

    test('nobody ran on either team: all DNF, refund', () {
      final results = evaluator.evaluate(_teamChallenge(
        entryFeeCoins: 10,
        participants: [
          _tp('u1', team: 'A', progress: 0),
          _tp('u2', team: 'B', progress: 0),
        ],
      ));

      expect(results.every((r) => r.outcome == ParticipantOutcome.didNotFinish),
          isTrue);
      expect(results.every((r) => r.coinsEarned == 10), isTrue);
    });
  });

  group('team vs team pace', () {
    test('team with lower avg pace wins', () {
      final results = evaluator.evaluate(_teamChallenge(
        metric: ChallengeMetric.pace,
        participants: [
          _tp('u1', team: 'A', progress: 300, sessions: ['s1']),
          _tp('u2', team: 'A', progress: 280, sessions: ['s2']),
          _tp('u3', team: 'B', progress: 320, sessions: ['s3']),
          _tp('u4', team: 'B', progress: 310, sessions: ['s4']),
        ],
      ));

      // Team A avg: (300+280)/2 = 290, Team B avg: (320+310)/2 = 315
      // Lower is better for pace, so Team A wins
      final winners = results.where((r) => r.outcome == ParticipantOutcome.won);
      expect(winners.length, 2);
      expect(winners.every((r) => r.userId == 'u1' || r.userId == 'u2'), isTrue);
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
