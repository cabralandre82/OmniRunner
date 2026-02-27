import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

/// Pure, stateless ranking engine for challenge evaluation.
///
/// Encapsulates all sorting, tie-breaking, and reward logic per goal type.
/// No I/O, no repos — takes data in, returns results out.
///
/// Goal-based rules:
/// - **fastestAtDistance**: lower elapsed time wins (completed target distance).
/// - **mostDistance**: higher accumulated distance wins.
/// - **bestPaceAtDistance**: lower pace (sec/km) wins (at target distance).
/// - **collectiveDistance**: team cooperative — each team sums km, team with more wins.
///
/// Tie-break: participant who submitted last session earliest wins.
///
/// OmniCoins are ONLY acquired via assessoria or won in staked challenges.
/// Free challenges (entryFeeCoins == 0) award ZERO coins.
final class ChallengeEvaluator {
  const ChallengeEvaluator();

  List<ParticipantResult> evaluate(ChallengeEntity challenge) {
    final accepted = challenge.participants
        .where((p) => p.status == ParticipantStatus.accepted)
        .toList();

    final List<ParticipantResult> results;
    if (challenge.type == ChallengeType.oneVsOne) {
      results = _evaluateOneVsOne(accepted, challenge);
    } else if (challenge.type == ChallengeType.team) {
      results = _evaluateTeam(accepted, challenge);
    } else if (challenge.rules.goal == ChallengeGoal.collectiveDistance) {
      // Legacy fallback: group + collectiveDistance created before this fix.
      results = _evaluateCollective(accepted, challenge);
    } else {
      results = _evaluateGroupCompetitive(accepted, challenge);
    }

    for (final p in challenge.participants) {
      if (p.status != ParticipantStatus.accepted) {
        results.add(ParticipantResult(
          userId: p.userId,
          finalValue: 0,
          outcome: ParticipantOutcome.didNotFinish,
          coinsEarned: 0,
          sessionIds: p.contributingSessionIds,
        ));
      }
    }

    return results;
  }

  List<ChallengeParticipantEntity> _sort(
    List<ChallengeParticipantEntity> participants,
    ChallengeGoal goal,
  ) {
    final sorted = List<ChallengeParticipantEntity>.of(participants);
    final lowerIsBetter = _isLowerBetter(goal);

    sorted.sort((a, b) {
      final int cmp;
      if (lowerIsBetter) {
        cmp = a.progressValue.compareTo(b.progressValue);
      } else {
        cmp = b.progressValue.compareTo(a.progressValue);
      }
      if (cmp != 0) return cmp;

      final aMs = a.lastSubmittedAtMs ?? _maxTimestamp;
      final bMs = b.lastSubmittedAtMs ?? _maxTimestamp;
      return aMs.compareTo(bMs);
    });

    return sorted;
  }

  List<ParticipantResult> _evaluateOneVsOne(
    List<ChallengeParticipantEntity> accepted,
    ChallengeEntity challenge,
  ) {
    if (accepted.isEmpty) return [];

    final ranked = _sort(accepted, challenge.rules.goal);
    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;

    if (ranked.every((p) => p.contributingSessionIds.isEmpty)) {
      return ranked
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: p.progressValue,
                rank: 1,
                outcome: ParticipantOutcome.didNotFinish,
                coinsEarned: hasStake ? stake : 0,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    if (ranked.length == 1) {
      return [
        ParticipantResult(
          userId: ranked[0].userId,
          finalValue: ranked[0].progressValue,
          rank: 1,
          outcome: ParticipantOutcome.won,
          coinsEarned: hasStake ? stake * 2 : 0,
          sessionIds: ranked[0].contributingSessionIds,
        ),
      ];
    }

    final first = ranked[0];
    final second = ranked[1];

    final firstRan = first.contributingSessionIds.isNotEmpty;
    final secondRan = second.contributingSessionIds.isNotEmpty;

    if (firstRan && !secondRan) {
      return [
        ParticipantResult(
          userId: first.userId,
          finalValue: first.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.won,
          coinsEarned: hasStake ? stake * 2 : 0,
          sessionIds: first.contributingSessionIds,
        ),
        ParticipantResult(
          userId: second.userId,
          finalValue: second.progressValue,
          rank: 2,
          outcome: ParticipantOutcome.didNotFinish,
          coinsEarned: 0,
          sessionIds: second.contributingSessionIds,
        ),
      ];
    }
    if (!firstRan && secondRan) {
      return [
        ParticipantResult(
          userId: second.userId,
          finalValue: second.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.won,
          coinsEarned: hasStake ? stake * 2 : 0,
          sessionIds: second.contributingSessionIds,
        ),
        ParticipantResult(
          userId: first.userId,
          finalValue: first.progressValue,
          rank: 2,
          outcome: ParticipantOutcome.didNotFinish,
          coinsEarned: 0,
          sessionIds: first.contributingSessionIds,
        ),
      ];
    }

    final isTrueTie = first.progressValue == second.progressValue &&
        _sameTiebreaker(first, second);

    if (isTrueTie) {
      return [
        ParticipantResult(
          userId: first.userId,
          finalValue: first.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: hasStake ? stake : 0,
          sessionIds: first.contributingSessionIds,
        ),
        ParticipantResult(
          userId: second.userId,
          finalValue: second.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: hasStake ? stake : 0,
          sessionIds: second.contributingSessionIds,
        ),
      ];
    }

    return [
      ParticipantResult(
        userId: first.userId,
        finalValue: first.progressValue,
        rank: 1,
        outcome: ParticipantOutcome.won,
        coinsEarned: hasStake ? stake * 2 : 0,
        sessionIds: first.contributingSessionIds,
      ),
      ParticipantResult(
        userId: second.userId,
        finalValue: second.progressValue,
        rank: 2,
        outcome: ParticipantOutcome.lost,
        coinsEarned: 0,
        sessionIds: second.contributingSessionIds,
      ),
    ];
  }

  /// Group competitive: individual ranking, top performer wins.
  List<ParticipantResult> _evaluateGroupCompetitive(
    List<ChallengeParticipantEntity> accepted,
    ChallengeEntity challenge,
  ) {
    if (accepted.isEmpty) return [];

    final ranked = _sort(accepted, challenge.rules.goal);
    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final pool = stake * ranked.length;

    final runners = ranked.where(
      (p) => p.contributingSessionIds.isNotEmpty,
    ).toList();

    if (runners.isEmpty) {
      return ranked
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: 0,
                outcome: ParticipantOutcome.didNotFinish,
                coinsEarned: hasStake ? stake : 0,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    final results = <ParticipantResult>[];
    int currentRank = 1;

    for (int i = 0; i < ranked.length; i++) {
      final p = ranked[i];
      if (i > 0 && p.progressValue != ranked[i - 1].progressValue) {
        currentRank = i + 1;
      }

      final didRun = p.contributingSessionIds.isNotEmpty;
      final ParticipantOutcome outcome;
      final int coins;

      if (!didRun) {
        outcome = ParticipantOutcome.didNotFinish;
        coins = 0;
      } else if (currentRank == 1) {
        outcome = ParticipantOutcome.won;
        final winnersCount = ranked.where(
          (x) => x.contributingSessionIds.isNotEmpty &&
                 x.progressValue == ranked[0].progressValue,
        ).length;
        coins = hasStake ? pool ~/ winnersCount : 0;
      } else {
        outcome = ParticipantOutcome.participated;
        coins = 0;
      }

      results.add(ParticipantResult(
        userId: p.userId,
        finalValue: p.progressValue,
        rank: currentRank,
        outcome: outcome,
        coinsEarned: coins,
        sessionIds: p.contributingSessionIds,
      ));
    }

    return results;
  }

  /// Legacy group cooperative fallback (pre-team migration).
  List<ParticipantResult> _evaluateCollective(
    List<ChallengeParticipantEntity> accepted,
    ChallengeEntity challenge,
  ) {
    final target = challenge.rules.target;
    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final pool = stake * accepted.length;

    final runners = accepted.where(
      (p) => p.contributingSessionIds.isNotEmpty,
    ).toList();

    if (runners.isEmpty) {
      return accepted
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: 0,
                outcome: ParticipantOutcome.didNotFinish,
                coinsEarned: hasStake ? stake : 0,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    final totalDistance =
        runners.map((p) => p.progressValue).reduce((a, b) => a + b);
    final groupMetTarget = target == null || totalDistance >= target;

    if (groupMetTarget) {
      final coinsEach = hasStake ? pool ~/ accepted.length : 0;
      return accepted
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: p.progressValue,
                outcome: ParticipantOutcome.completedTarget,
                coinsEarned: coinsEach,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    return accepted
        .map((p) => ParticipantResult(
              userId: p.userId,
              finalValue: p.progressValue,
              outcome: ParticipantOutcome.participated,
              coinsEarned: 0,
              sessionIds: p.contributingSessionIds,
            ))
        .toList();
  }

  /// Team vs Team: aggregate each team's result, winning team splits the pool.
  ///
  /// Scoring per goal:
  /// - **fastestAtDistance**: team time = last member to finish (all must run).
  /// - **mostDistance**: team distance = sum of all members' distances.
  /// - **bestPaceAtDistance**: team pace = average pace of members who ran.
  List<ParticipantResult> _evaluateTeam(
    List<ChallengeParticipantEntity> accepted,
    ChallengeEntity challenge,
  ) {
    if (accepted.isEmpty) return [];

    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final pool = stake * accepted.length;
    final goal = challenge.rules.goal;

    final teamA = accepted.where((p) => p.team == 'A').toList();
    final teamB = accepted.where((p) => p.team == 'B').toList();

    final runnersA = teamA.where((p) => p.contributingSessionIds.isNotEmpty).toList();
    final runnersB = teamB.where((p) => p.contributingSessionIds.isNotEmpty).toList();

    // Nobody ran → all DNF, refund stakes.
    if (runnersA.isEmpty && runnersB.isEmpty) {
      return accepted
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: 0,
                outcome: ParticipantOutcome.didNotFinish,
                coinsEarned: hasStake ? stake : 0,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    final scoreA = _teamScore(runnersA, teamA.length, goal);
    final scoreB = _teamScore(runnersB, teamB.length, goal);

    // If one team has no runners, the other auto-wins.
    final bool teamAWins;
    final bool isTied;
    if (runnersA.isEmpty) {
      teamAWins = false;
      isTied = false;
    } else if (runnersB.isEmpty) {
      teamAWins = true;
      isTied = false;
    } else {
      final lowerIsBetter = _isLowerBetter(goal);
      final cmp = lowerIsBetter
          ? scoreA.compareTo(scoreB)
          : scoreB.compareTo(scoreA);
      if (cmp < 0) {
        teamAWins = true;
        isTied = false;
      } else if (cmp > 0) {
        teamAWins = false;
        isTied = false;
      } else {
        teamAWins = false;
        isTied = true;
      }
    }

    final results = <ParticipantResult>[];

    for (final p in accepted) {
      final isA = p.team == 'A';
      final myTeamWon = isA ? teamAWins : (!teamAWins && !isTied);

      final ParticipantOutcome outcome;
      final int coins;

      if (isTied) {
        outcome = ParticipantOutcome.tied;
        coins = hasStake ? stake : 0;
      } else if (myTeamWon) {
        outcome = ParticipantOutcome.won;
        final winnerCount = isA ? teamA.length : teamB.length;
        coins = hasStake && winnerCount > 0 ? pool ~/ winnerCount : 0;
      } else {
        outcome = ParticipantOutcome.lost;
        coins = 0;
      }

      results.add(ParticipantResult(
        userId: p.userId,
        finalValue: p.progressValue,
        outcome: outcome,
        coinsEarned: coins,
        sessionIds: p.contributingSessionIds,
      ));
    }

    return results;
  }

  /// Compute a single aggregate score for one team.
  static double _teamScore(
    List<ChallengeParticipantEntity> runners,
    int teamSize,
    ChallengeGoal goal,
  ) {
    if (runners.isEmpty) return _isLowerBetter(goal) ? double.infinity : 0;

    return switch (goal) {
      // Last member to finish: worst (highest) time among runners.
      // If not all members ran, penalize with infinity.
      ChallengeGoal.fastestAtDistance => runners.length < teamSize
          ? double.infinity
          : runners.map((p) => p.progressValue).reduce((a, b) => a > b ? a : b),
      // Sum of distances.
      ChallengeGoal.mostDistance =>
          runners.map((p) => p.progressValue).reduce((a, b) => a + b),
      // Average pace of runners.
      ChallengeGoal.bestPaceAtDistance =>
          runners.map((p) => p.progressValue).reduce((a, b) => a + b) /
              runners.length,
      // collectiveDistance should not reach here but handle gracefully.
      ChallengeGoal.collectiveDistance =>
          runners.map((p) => p.progressValue).reduce((a, b) => a + b),
    };
  }

  static bool _sameTiebreaker(
    ChallengeParticipantEntity a,
    ChallengeParticipantEntity b,
  ) {
    final aMs = a.lastSubmittedAtMs;
    final bMs = b.lastSubmittedAtMs;
    if (aMs == null && bMs == null) return true;
    return aMs == bMs;
  }

  /// fastestAtDistance and bestPaceAtDistance: lower value wins.
  /// mostDistance and collectiveDistance: higher value wins.
  static bool _isLowerBetter(ChallengeGoal goal) =>
      goal == ChallengeGoal.fastestAtDistance ||
      goal == ChallengeGoal.bestPaceAtDistance;

  static const _maxTimestamp = 0x7FFFFFFFFFFFFFFF;
}
