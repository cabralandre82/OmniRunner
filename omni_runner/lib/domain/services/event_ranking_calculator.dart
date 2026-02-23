import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';
import 'package:omni_runner/domain/entities/race_result_entity.dart';

/// Pure, stateless ranking engine for coaching race events.
///
/// No I/O, no repos — takes pre-fetched participations and the event in,
/// returns ranked [RaceResultEntity] list out.
///
/// Ranking rules per [RaceEventMetric]:
/// - **distance**: higher `totalDistanceM` is better
/// - **time**: higher `totalMovingMs` is better (more training volume)
/// - **pace**: lower `bestPaceSecPerKm` is better
///
/// Dense ranking with skip: ties share the same rank, next rank skips.
/// Example: 1, 1, 3 — not 1, 1, 2.
///
/// Reward distribution:
/// - **Completers** (targetCompleted): receive full `xpReward` + `coinsReward` + `badgeId`
/// - **Participants** (≥ 1 session, not completed): receive participation XP
///   (`participationXpPercent` of `xpReward`, default 20%)
/// - **Zero sessions**: receive 0 rewards
final class EventRankingCalculator {
  /// Fraction of `xpReward` granted to non-completers who participated.
  final double participationXpPercent;

  const EventRankingCalculator({
    this.participationXpPercent = 0.20,
  });

  /// Compute final results for all participants of a race event.
  ///
  /// [event] is the race being settled.
  /// [participations] is the list of all enrolled athletes.
  /// [idGenerator] produces a UUID for each result (keyed by userId).
  /// [nowMs] is the timestamp for `computedAtMs`.
  List<RaceResultEntity> compute({
    required RaceEventEntity event,
    required List<RaceParticipationEntity> participations,
    required String Function(String userId) idGenerator,
    required int nowMs,
  }) {
    if (participations.isEmpty) return const [];

    final scored = participations.map((p) => _score(p, event.metric)).toList();

    final isLower = event.metric == RaceEventMetric.pace;
    scored.sort((a, b) => isLower
        ? a.sortValue.compareTo(b.sortValue)
        : b.sortValue.compareTo(a.sortValue));

    _assignRanks(scored);

    return scored.map((s) {
      final xp = _computeXp(s, event);
      final coins = _computeCoins(s, event);
      final badge = s.targetCompleted ? event.badgeId : null;

      return RaceResultEntity(
        id: idGenerator(s.userId),
        raceEventId: event.id,
        userId: s.userId,
        displayName: s.displayName,
        finalRank: s.rank,
        totalDistanceM: s.totalDistanceM,
        totalMovingMs: s.totalMovingMs,
        bestPaceSecPerKm: s.bestPaceSecPerKm,
        sessionCount: s.sessionCount,
        targetCompleted: s.targetCompleted,
        xpAwarded: xp,
        coinsAwarded: coins,
        badgeId: badge,
        computedAtMs: nowMs,
      );
    }).toList();
  }

  // ── Scoring ──

  _ScoredParticipant _score(
    RaceParticipationEntity p,
    RaceEventMetric metric,
  ) {
    final double sortValue;
    switch (metric) {
      case RaceEventMetric.distance:
        sortValue = p.totalDistanceM;
      case RaceEventMetric.time:
        sortValue = p.totalMovingMs.toDouble();
      case RaceEventMetric.pace:
        sortValue = p.bestPaceSecPerKm ?? double.infinity;
    }

    return _ScoredParticipant(
      userId: p.userId,
      displayName: p.displayName,
      sortValue: sortValue,
      totalDistanceM: p.totalDistanceM,
      totalMovingMs: p.totalMovingMs,
      bestPaceSecPerKm: p.bestPaceSecPerKm,
      sessionCount: p.contributingSessionCount,
      targetCompleted: p.completed,
    );
  }

  // ── Dense ranking with skip ──

  void _assignRanks(List<_ScoredParticipant> sorted) {
    if (sorted.isEmpty) return;

    int currentRank = 1;
    sorted.first.rank = 1;

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].sortValue != sorted[i - 1].sortValue) {
        currentRank = i + 1;
      }
      sorted[i].rank = currentRank;
    }
  }

  // ── Reward computation ──

  int _computeXp(_ScoredParticipant s, RaceEventEntity event) {
    if (event.xpReward <= 0) return 0;
    if (s.targetCompleted) return event.xpReward;
    if (s.sessionCount > 0) {
      return (event.xpReward * participationXpPercent).round();
    }
    return 0;
  }

  int _computeCoins(_ScoredParticipant s, RaceEventEntity event) {
    if (event.coinsReward <= 0) return 0;
    if (s.targetCompleted) return event.coinsReward;
    return 0;
  }
}

class _ScoredParticipant {
  final String userId;
  final String displayName;
  final double sortValue;
  final double totalDistanceM;
  final int totalMovingMs;
  final double? bestPaceSecPerKm;
  final int sessionCount;
  final bool targetCompleted;

  int rank = 0;

  _ScoredParticipant({
    required this.userId,
    required this.displayName,
    required this.sortValue,
    required this.totalDistanceM,
    required this.totalMovingMs,
    required this.bestPaceSecPerKm,
    required this.sessionCount,
    required this.targetCompleted,
  });
}
