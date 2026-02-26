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
/// OmniCoins are ONLY acquired via assessoria or won in staked challenges.
/// Free challenges (entryFeeCoins == 0) award ZERO coins.
/// Staked challenges: entry fees form a pool, winner takes the pool.
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

    // Nobody submitted anything → both DNF. Refund entry fee if staked.
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
          coinsEarned: hasStake ? stake * 2 : 0,
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

  /// Group evaluation — cooperative.
  ///
  /// The group wins or loses as a unit (same logic as team vs team).
  /// Collective progress = sum of all runners (distance/time) or
  /// average (pace). If the group meets the target, ALL members
  /// share the reward equally — runners and non-runners alike.
  /// If nobody ran → everyone DNF, refund stakes.
  ///
  /// Pool = entry_fee_coins * total_accepted_participants.
  List<ParticipantResult> _evaluateGroup(
    List<ChallengeParticipantEntity> ranked,
    ChallengeEntity challenge,
  ) {
    final target = challenge.rules.target;
    final stake = challenge.rules.entryFeeCoins;
    final hasStake = stake > 0;
    final pool = stake * ranked.length;
    final lowerIsBetter = _isLowerBetter(challenge.rules.metric);

    final runners = ranked.where(
      (p) => p.contributingSessionIds.isNotEmpty,
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

    // Collective progress from runners.
    final bool groupMetTarget;
    if (target == null) {
      groupMetTarget = true;
    } else if (lowerIsBetter) {
      final avg = runners.map((p) => p.progressValue).reduce((a, b) => a + b) /
          runners.length;
      groupMetTarget = avg > 0 && avg <= target;
    } else {
      final total =
          runners.map((p) => p.progressValue).reduce((a, b) => a + b);
      groupMetTarget = total >= target;
    }

    if (groupMetTarget) {
      final coinsEach = hasStake ? pool ~/ ranked.length : 0;
      return ranked
          .map((p) => ParticipantResult(
                userId: p.userId,
                finalValue: p.progressValue,
                outcome: ParticipantOutcome.completedTarget,
                coinsEarned: coinsEach,
                sessionIds: p.contributingSessionIds,
              ))
          .toList();
    }

    // Group didn't meet target — everyone participated but no reward.
    return ranked
        .map((p) => ParticipantResult(
              userId: p.userId,
              finalValue: p.progressValue,
              outcome: ParticipantOutcome.participated,
              coinsEarned: 0,
              sessionIds: p.contributingSessionIds,
            ))
        .toList();
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
  /// The team wins or loses as a unit.
  /// Score per team = sum of progressValues of members who ran.
  /// Pool is split equally among ALL members of the winning team
  /// (runners and non-runners alike — the entry fee is per person,
  /// so the pool belongs to the whole team).
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
      final int coinsPerMember;
      if (tied) {
        coinsPerMember = ranked.isNotEmpty ? pool ~/ ranked.length : 0;
      } else if (isWinner && team.isNotEmpty) {
        coinsPerMember = pool ~/ team.length;
      } else {
        coinsPerMember = 0;
      }

      final outcome = tied
          ? ParticipantOutcome.tied
          : isWinner
              ? ParticipantOutcome.won
              : ParticipantOutcome.lost;

      return team.map((p) => ParticipantResult(
        userId: p.userId,
        finalValue: p.progressValue,
        outcome: outcome,
        coinsEarned: coinsPerMember,
        sessionIds: p.contributingSessionIds,
      )).toList();
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
