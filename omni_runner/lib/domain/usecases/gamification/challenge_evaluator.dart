import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

/// Pure, stateless ranking engine for challenge evaluation.
///
/// Encapsulates all sorting, tie-breaking, and reward logic.
/// No I/O, no repos — takes data in, returns results out.
///
/// Rules:
/// - **1v1 pace**: lower value wins.
/// - **1v1 distance/time**: higher value wins.
/// - **Group pace**: lower value wins.
/// - **Group distance/time**: higher value wins.
/// - **Tie-break**: participant who submitted their last session
///   earliest (`lastSubmittedAtMs`) wins. If still tied, both share
///   the rank and get equal rewards.
///
/// Coin rewards (from GAMIFICATION_POLICY.md §3/§4):
/// - 1v1 winner: 25 (participation) + 15 (bonus) = 40
/// - 1v1 loser:  25 (participation)
/// - 1v1 tied:   25 + 15 = 40 each
/// - Group met target: 30
/// - Group did not meet target: 0
/// - No sessions submitted: 0 (participated)
final class ChallengeEvaluator {
  const ChallengeEvaluator();

  /// Evaluate all accepted participants and produce ranked results.
  ///
  /// [challenge] must be active or completing.
  /// Returns a list of [ParticipantResult] for accepted participants,
  /// plus DNF entries for non-accepted participants.
  List<ParticipantResult> evaluate(ChallengeEntity challenge) {
    final accepted = challenge.participants
        .where((p) => p.status == ParticipantStatus.accepted)
        .toList();

    final ranked = _sort(accepted, challenge.rules.metric);

    final List<ParticipantResult> results;
    if (challenge.type == ChallengeType.oneVsOne) {
      results = _evaluateOneVsOne(ranked, challenge);
    } else if (challenge.type == ChallengeType.teamVsTeam) {
      results = _evaluateTeamVsTeam(ranked, challenge);
    } else {
      results = _evaluateGroup(ranked, challenge);
    }

    // Append DNF for non-accepted participants.
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

  /// Sort participants by their progress value, applying the
  /// `earliestFinish` tiebreaker.
  List<ChallengeParticipantEntity> _sort(
    List<ChallengeParticipantEntity> participants,
    ChallengeMetric metric,
  ) {
    final sorted = List<ChallengeParticipantEntity>.of(participants);
    final lowerIsBetter = _isLowerBetter(metric);

    sorted.sort((a, b) {
      final int cmp;
      if (lowerIsBetter) {
        cmp = a.progressValue.compareTo(b.progressValue);
      } else {
        cmp = b.progressValue.compareTo(a.progressValue);
      }
      if (cmp != 0) return cmp;

      // Tiebreaker: earliestFinish wins (lower timestamp = earlier).
      final aMs = a.lastSubmittedAtMs ?? _maxTimestamp;
      final bMs = b.lastSubmittedAtMs ?? _maxTimestamp;
      return aMs.compareTo(bMs);
    });

    return sorted;
  }

  List<ParticipantResult> _evaluateOneVsOne(
    List<ChallengeParticipantEntity> ranked,
    ChallengeEntity challenge,
  ) {
    if (ranked.isEmpty) return [];

    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;

    // Nobody submitted anything → both lose. Refund entry fee if any.
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

    // Only one accepted participant → auto-win.
    if (ranked.length == 1) {
      return [
        ParticipantResult(
          userId: ranked[0].userId,
          finalValue: ranked[0].progressValue,
          rank: 1,
          outcome: ParticipantOutcome.won,
          coinsEarned: hasStake ? stake * 2 : 25 + 15,
          sessionIds: ranked[0].contributingSessionIds,
        ),
      ];
    }

    final first = ranked[0];
    final second = ranked[1];

    final firstRan = first.contributingSessionIds.isNotEmpty;
    final secondRan = second.contributingSessionIds.isNotEmpty;

    // One completed, the other didn't → completer wins automatically.
    if (firstRan && !secondRan) {
      return [
        ParticipantResult(
          userId: first.userId,
          finalValue: first.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.won,
          coinsEarned: hasStake ? stake * 2 : 25 + 15,
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
          coinsEarned: hasStake ? stake * 2 : 25 + 15,
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

    // Both ran — compare results normally.
    final isTrueTie = first.progressValue == second.progressValue &&
        _sameTiebreaker(first, second);

    if (isTrueTie) {
      return [
        ParticipantResult(
          userId: first.userId,
          finalValue: first.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: hasStake ? stake : 25 + 15,
          sessionIds: first.contributingSessionIds,
        ),
        ParticipantResult(
          userId: second.userId,
          finalValue: second.progressValue,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: hasStake ? stake : 25 + 15,
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
        coinsEarned: hasStake ? stake * 2 : 25 + 15,
        sessionIds: first.contributingSessionIds,
      ),
      ParticipantResult(
        userId: second.userId,
        finalValue: second.progressValue,
        rank: 2,
        outcome: ParticipantOutcome.lost,
        coinsEarned: hasStake ? 0 : 25,
        sessionIds: second.contributingSessionIds,
      ),
    ];
  }

  List<ParticipantResult> _evaluateGroup(
    List<ChallengeParticipantEntity> ranked,
    ChallengeEntity challenge,
  ) {
    final target = challenge.rules.target;
    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final lowerIsBetter = _isLowerBetter(challenge.rules.metric);

    final runners = ranked.where(
      (p) => p.contributingSessionIds.isNotEmpty,
    ).toList();
    final noRun = ranked.where(
      (p) => p.contributingSessionIds.isEmpty,
    ).toList();

    // Nobody ran → everyone DNF, refund stakes.
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

    // Rank only runners.
    final sortedRunners = _sort(runners, challenge.rules.metric);
    final ranks = _assignDenseRanks(sortedRunners, challenge.rules.metric);

    final results = <ParticipantResult>[];

    for (var i = 0; i < sortedRunners.length; i++) {
      final p = sortedRunners[i];
      final rank = ranks[i];

      final bool metTarget;
      if (target == null) {
        metTarget = true;
      } else if (lowerIsBetter) {
        metTarget = p.progressValue > 0 && p.progressValue <= target;
      } else {
        metTarget = p.progressValue >= target;
      }

      results.add(ParticipantResult(
        userId: p.userId,
        finalValue: p.progressValue,
        rank: rank,
        outcome: metTarget
            ? ParticipantOutcome.completedTarget
            : ParticipantOutcome.participated,
        coinsEarned: metTarget ? 30 : 0,
        sessionIds: p.contributingSessionIds,
      ));
    }

    // Non-runners are DNF, 0 coins (they lost).
    for (final p in noRun) {
      results.add(ParticipantResult(
        userId: p.userId,
        finalValue: 0,
        outcome: ParticipantOutcome.didNotFinish,
        coinsEarned: 0,
        sessionIds: p.contributingSessionIds,
      ));
    }

    return results;
  }

  /// Dense ranking: tied participants share the same rank.
  /// e.g. [1, 1, 3] not [1, 1, 2].
  List<int> _assignDenseRanks(
    List<ChallengeParticipantEntity> sorted,
    ChallengeMetric metric,
  ) {
    if (sorted.isEmpty) return [];
    final ranks = List<int>.filled(sorted.length, 1);
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].progressValue == sorted[i - 1].progressValue &&
          _sameTiebreaker(sorted[i], sorted[i - 1])) {
        ranks[i] = ranks[i - 1];
      } else {
        ranks[i] = i + 1;
      }
    }
    return ranks;
  }

  /// Whether two participants cannot be differentiated by the tiebreaker.
  static bool _sameTiebreaker(
    ChallengeParticipantEntity a,
    ChallengeParticipantEntity b,
  ) {
    final aMs = a.lastSubmittedAtMs;
    final bMs = b.lastSubmittedAtMs;
    if (aMs == null && bMs == null) return true;
    return aMs == bMs;
  }

  /// Team vs Team evaluation.
  ///
  /// Score per team = sum of progressValues of members who actually ran.
  /// Members who didn't run are DNF (0 coins, regardless of team outcome).
  /// Pool is split only among winning team members who ran.
  /// If nobody on either team ran → everyone DNF, refund stakes.
  ///
  /// Pool = entry_fee_coins * total_accepted_participants.
  List<ParticipantResult> _evaluateTeamVsTeam(
    List<ChallengeParticipantEntity> ranked,
    ChallengeEntity challenge,
  ) {
    if (ranked.isEmpty) return [];

    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final pool = stake * ranked.length;

    final teamA = ranked.where((p) => p.team == 'A').toList();
    final teamB = ranked.where((p) => p.team == 'B').toList();

    // Nobody ran at all → everyone DNF, refund.
    if (ranked.every((p) => p.contributingSessionIds.isEmpty)) {
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

    final lowerIsBetter = _isLowerBetter(challenge.rules.metric);

    double teamScore(List<ChallengeParticipantEntity> team) {
      final active = team.where((p) => p.contributingSessionIds.isNotEmpty);
      if (active.isEmpty) return lowerIsBetter ? double.infinity : 0;
      if (lowerIsBetter) {
        return active.map((p) => p.progressValue).reduce((a, b) => a + b) /
            active.length;
      }
      return active.map((p) => p.progressValue).reduce((a, b) => a + b);
    }

    final scoreA = teamScore(teamA);
    final scoreB = teamScore(teamB);

    final int cmp;
    if (lowerIsBetter) {
      cmp = scoreA.compareTo(scoreB);
    } else {
      cmp = scoreB.compareTo(scoreA);
    }

    final bool teamAWins;
    final bool isTied;
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

    List<ParticipantResult> buildTeamResults(
      List<ChallengeParticipantEntity> team,
      bool isWinner,
      bool tied,
    ) {
      final runners = team.where(
        (p) => p.contributingSessionIds.isNotEmpty,
      ).toList();

      final int coinsPerRunner;
      if (tied) {
        final totalRunners = ranked
            .where((p) => p.contributingSessionIds.isNotEmpty)
            .length;
        coinsPerRunner = totalRunners > 0 ? pool ~/ totalRunners : 0;
      } else if (isWinner && runners.isNotEmpty) {
        coinsPerRunner = pool ~/ runners.length;
      } else {
        coinsPerRunner = 0;
      }

      return team.map((p) {
        final ran = p.contributingSessionIds.isNotEmpty;
        if (!ran) {
          return ParticipantResult(
            userId: p.userId,
            finalValue: 0,
            outcome: ParticipantOutcome.didNotFinish,
            coinsEarned: 0,
            sessionIds: p.contributingSessionIds,
          );
        }
        final outcome = tied
            ? ParticipantOutcome.tied
            : isWinner
                ? ParticipantOutcome.won
                : ParticipantOutcome.lost;
        return ParticipantResult(
          userId: p.userId,
          finalValue: p.progressValue,
          outcome: outcome,
          coinsEarned: coinsPerRunner,
          sessionIds: p.contributingSessionIds,
        );
      }).toList();
    }

    return [
      ...buildTeamResults(teamA, teamAWins, isTied),
      ...buildTeamResults(teamB, !teamAWins && !isTied, isTied),
    ];
  }

  /// Pace: lower is better (faster runner).
  /// Distance and Time: higher is better (more distance / more moving time).
  static bool _isLowerBetter(ChallengeMetric metric) =>
      metric == ChallengeMetric.pace;

  static const _maxTimestamp = 0x7FFFFFFFFFFFFFFF;
}
