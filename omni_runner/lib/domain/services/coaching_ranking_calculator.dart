import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';

/// Lightweight projection of a workout session for ranking computation.
///
/// The caller maps from [WorkoutSessionEntity] / Isar records to this DTO,
/// so the calculator stays free of persistence and entity coupling.
final class RankableSession {
  /// Total verified distance in meters.
  final double distanceM;

  /// Moving time in milliseconds (excludes pauses).
  final int movingMs;

  /// Average pace in sec/km. Null if the session has zero distance.
  final double? avgPaceSecPerKm;

  /// Session start time (ms since epoch, UTC) — used to derive calendar day.
  final int startTimeMs;

  const RankableSession({
    required this.distanceM,
    required this.movingMs,
    this.avgPaceSecPerKm,
    required this.startTimeMs,
  });
}

/// Per-athlete input bundle for ranking computation.
final class AthleteSessionData {
  final String userId;
  final String displayName;
  final List<RankableSession> sessions;

  const AthleteSessionData({
    required this.userId,
    required this.displayName,
    required this.sessions,
  });
}

/// Pure, stateless ranking engine for coaching groups.
///
/// No I/O, no repos — takes pre-fetched data in, returns a ranked snapshot.
///
/// Ranking rules:
/// - **volumeDistance**: sum of distance (higher is better)
/// - **totalTime**: sum of movingMs (higher is better)
/// - **bestPace**: lowest avgPace among sessions (lower is better)
/// - **consistencyDays**: distinct UTC calendar days with a session (higher is better)
///
/// Dense ranking with skip: ties share the same rank, next rank skips.
/// Example: 1, 1, 3 — not 1, 1, 2.
///
/// Athletes with zero qualifying sessions receive value 0 (or [double.infinity]
/// for bestPace) and are ranked last.
final class CoachingRankingCalculator {
  const CoachingRankingCalculator();

  /// Compute a ranking snapshot for one metric.
  CoachingGroupRankingEntity compute({
    required String rankingId,
    required String groupId,
    required CoachingRankingMetric metric,
    required CoachingRankingPeriod period,
    required String periodKey,
    required int startsAtMs,
    required int endsAtMs,
    required List<AthleteSessionData> athletes,
    required int nowMs,
  }) {
    final scored = athletes.map((a) => _score(a, metric)).toList();

    final isLower = metric == CoachingRankingMetric.bestPace;
    scored.sort((a, b) => isLower
        ? a.value.compareTo(b.value)
        : b.value.compareTo(a.value));

    final entries = _assignRanks(scored, isLower);

    return CoachingGroupRankingEntity(
      id: rankingId,
      groupId: groupId,
      metric: metric,
      period: period,
      periodKey: periodKey,
      startsAtMs: startsAtMs,
      endsAtMs: endsAtMs,
      entries: entries,
      computedAtMs: nowMs,
    );
  }

  /// Compute rankings for all four metrics at once.
  List<CoachingGroupRankingEntity> computeAll({
    required String groupId,
    required CoachingRankingPeriod period,
    required String periodKey,
    required int startsAtMs,
    required int endsAtMs,
    required List<AthleteSessionData> athletes,
    required int nowMs,
    required String Function(CoachingRankingMetric metric) idGenerator,
  }) {
    return CoachingRankingMetric.values
        .map((m) => compute(
              rankingId: idGenerator(m),
              groupId: groupId,
              metric: m,
              period: period,
              periodKey: periodKey,
              startsAtMs: startsAtMs,
              endsAtMs: endsAtMs,
              athletes: athletes,
              nowMs: nowMs,
            ))
        .toList();
  }

  // ── Metric scoring ──

  _ScoredAthlete _score(AthleteSessionData a, CoachingRankingMetric metric) {
    final sessions = a.sessions;
    final count = sessions.length;

    final double value;
    switch (metric) {
      case CoachingRankingMetric.volumeDistance:
        value = sessions.fold(0.0, (sum, s) => sum + s.distanceM);

      case CoachingRankingMetric.totalTime:
        value = sessions.fold(0.0, (sum, s) => sum + s.movingMs);

      case CoachingRankingMetric.bestPace:
        final paces = sessions
            .where((s) => s.avgPaceSecPerKm != null && s.avgPaceSecPerKm! > 0)
            .map((s) => s.avgPaceSecPerKm!)
            .toList();
        value = paces.isEmpty ? double.infinity : paces.reduce((a, b) => a < b ? a : b);

      case CoachingRankingMetric.consistencyDays:
        final days = <int>{};
        for (final s in sessions) {
          final dt = DateTime.fromMillisecondsSinceEpoch(s.startTimeMs, isUtc: true);
          days.add(dt.year * 10000 + dt.month * 100 + dt.day);
        }
        value = days.length.toDouble();
    }

    return _ScoredAthlete(
      userId: a.userId,
      displayName: a.displayName,
      value: value,
      sessionCount: count,
    );
  }

  // ── Rank assignment (dense with skip) ──

  List<CoachingRankingEntryEntity> _assignRanks(
    List<_ScoredAthlete> sorted,
    bool isLowerBetter,
  ) {
    if (sorted.isEmpty) return const [];

    final entries = <CoachingRankingEntryEntity>[];
    int currentRank = 1;

    for (int i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i].value != sorted[i - 1].value) {
        currentRank = i + 1;
      }
      entries.add(CoachingRankingEntryEntity(
        userId: sorted[i].userId,
        displayName: sorted[i].displayName,
        value: sorted[i].value,
        rank: currentRank,
        sessionCount: sorted[i].sessionCount,
      ));
    }

    return entries;
  }
}

class _ScoredAthlete {
  final String userId;
  final String displayName;
  final double value;
  final int sessionCount;

  const _ScoredAthlete({
    required this.userId,
    required this.displayName,
    required this.value,
    required this.sessionCount,
  });
}
