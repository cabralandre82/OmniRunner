import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/services/coaching_ranking_calculator.dart';

void main() {
  const calc = CoachingRankingCalculator();
  const msPerDay = 86400000;

  AthleteSessionData athlete(String id, List<RankableSession> sessions) =>
      AthleteSessionData(userId: id, displayName: 'Athlete $id', sessions: sessions);

  RankableSession session({
    double distanceM = 5000,
    int movingMs = 1800000,
    double? avgPace = 360,
    int day = 0,
  }) =>
      RankableSession(
        distanceM: distanceM,
        movingMs: movingMs,
        avgPaceSecPerKm: avgPace,
        startTimeMs: day * msPerDay,
      );

  group('CoachingRankingCalculator', () {
    test('volumeDistance ranks by total distance descending', () {
      final athletes = [
        athlete('a', [session(distanceM: 5000), session(distanceM: 3000)]),
        athlete('b', [session(distanceM: 10000)]),
        athlete('c', [session(distanceM: 2000)]),
      ];

      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.volumeDistance,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
      );

      expect(result.entries[0].userId, 'b');
      expect(result.entries[0].rank, 1);
      expect(result.entries[0].value, 10000);
      expect(result.entries[1].userId, 'a');
      expect(result.entries[1].rank, 2);
      expect(result.entries[1].value, 8000);
      expect(result.entries[2].userId, 'c');
      expect(result.entries[2].rank, 3);
    });

    test('bestPace ranks by lowest pace ascending', () {
      final athletes = [
        athlete('a', [session(avgPace: 360)]),
        athlete('b', [session(avgPace: 300), session(avgPace: 340)]),
        athlete('c', [session(avgPace: 320)]),
      ];

      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.bestPace,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
      );

      expect(result.entries[0].userId, 'b');
      expect(result.entries[0].value, 300);
      expect(result.entries[0].rank, 1);
      expect(result.entries[1].userId, 'c');
      expect(result.entries[1].rank, 2);
      expect(result.entries[2].userId, 'a');
      expect(result.entries[2].rank, 3);
    });

    test('consistencyDays counts distinct UTC calendar days', () {
      final athletes = [
        athlete('a', [
          session(day: 0),
          session(day: 0), // same day
          session(day: 1),
        ]),
        athlete('b', [
          session(day: 0),
          session(day: 1),
          session(day: 2),
          session(day: 3),
        ]),
      ];

      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.consistencyDays,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
      );

      expect(result.entries[0].userId, 'b');
      expect(result.entries[0].value, 4);
      expect(result.entries[1].userId, 'a');
      expect(result.entries[1].value, 2);
    });

    test('ties share the same rank with skip', () {
      final athletes = [
        athlete('a', [session(distanceM: 5000)]),
        athlete('b', [session(distanceM: 5000)]),
        athlete('c', [session(distanceM: 3000)]),
      ];

      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.volumeDistance,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
      );

      expect(result.entries[0].rank, 1);
      expect(result.entries[1].rank, 1);
      expect(result.entries[2].rank, 3);
    });

    test('athletes with no sessions get infinity pace and rank last', () {
      final athletes = [
        athlete('a', [session(avgPace: 300)]),
        athlete('b', []),
      ];

      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.bestPace,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
      );

      expect(result.entries[0].userId, 'a');
      expect(result.entries[0].rank, 1);
      expect(result.entries[1].userId, 'b');
      expect(result.entries[1].value, double.infinity);
    });

    test('computeAll returns rankings for all 4 metrics', () {
      final athletes = [
        athlete('a', [session()]),
      ];

      final results = calc.computeAll(
        groupId: 'g-1',
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: athletes,
        nowMs: 7 * msPerDay,
        idGenerator: (m) => 'id-${m.name}',
      );

      expect(results.length, CoachingRankingMetric.values.length);
    });

    test('empty athletes produces empty entries', () {
      final result = calc.compute(
        rankingId: 'r-1',
        groupId: 'g-1',
        metric: CoachingRankingMetric.volumeDistance,
        period: CoachingRankingPeriod.weekly,
        periodKey: '2026-W08',
        startsAtMs: 0,
        endsAtMs: 7 * msPerDay,
        athletes: [],
        nowMs: 7 * msPerDay,
      );

      expect(result.entries, isEmpty);
    });
  });
}
