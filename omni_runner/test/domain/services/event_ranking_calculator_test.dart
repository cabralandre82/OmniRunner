import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';
import 'package:omni_runner/domain/services/event_ranking_calculator.dart';

void main() {
  const calc = EventRankingCalculator();

  RaceEventEntity makeEvent({
    RaceEventMetric metric = RaceEventMetric.distance,
    double? targetDistanceM = 10000,
    int xpReward = 100,
    int coinsReward = 50,
    String? badgeId,
  }) =>
      RaceEventEntity(
        id: 'evt-1',
        groupId: 'g1',
        title: 'Race',
        metric: metric,
        targetDistanceM: targetDistanceM,
        startsAtMs: 0,
        endsAtMs: 100000,
        status: RaceEventStatus.completed,
        createdByUserId: 'coach',
        createdAtMs: 0,
        xpReward: xpReward,
        coinsReward: coinsReward,
        badgeId: badgeId,
      );

  RaceParticipationEntity makePart({
    required String userId,
    String displayName = '',
    double totalDistanceM = 0,
    int totalMovingMs = 0,
    double? bestPaceSecPerKm,
    int sessionCount = 0,
    bool completed = false,
  }) =>
      RaceParticipationEntity(
        id: 'p-$userId',
        raceEventId: 'evt-1',
        userId: userId,
        displayName: displayName.isEmpty ? userId : displayName,
        joinedAtMs: 0,
        totalDistanceM: totalDistanceM,
        totalMovingMs: totalMovingMs,
        bestPaceSecPerKm: bestPaceSecPerKm,
        contributingSessionCount: sessionCount,
        completed: completed,
      );

  String idGen(String userId) => 'result-$userId';
  const now = 999999;

  group('EventRankingCalculator', () {
    test('returns empty list for empty participations', () {
      final results = calc.compute(
        event: makeEvent(),
        participations: [],
        idGenerator: idGen,
        nowMs: now,
      );
      expect(results, isEmpty);
    });

    test('ranks by distance (higher is better)', () {
      final results = calc.compute(
        event: makeEvent(metric: RaceEventMetric.distance),
        participations: [
          makePart(userId: 'u1', totalDistanceM: 5000),
          makePart(userId: 'u2', totalDistanceM: 8000),
          makePart(userId: 'u3', totalDistanceM: 3000),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].userId, 'u2');
      expect(results[0].finalRank, 1);
      expect(results[1].userId, 'u1');
      expect(results[1].finalRank, 2);
      expect(results[2].userId, 'u3');
      expect(results[2].finalRank, 3);
    });

    test('ranks by pace (lower is better)', () {
      final results = calc.compute(
        event: makeEvent(metric: RaceEventMetric.pace),
        participations: [
          makePart(userId: 'u1', bestPaceSecPerKm: 300),
          makePart(userId: 'u2', bestPaceSecPerKm: 250),
          makePart(userId: 'u3', bestPaceSecPerKm: 350),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].userId, 'u2');
      expect(results[0].finalRank, 1);
      expect(results[2].userId, 'u3');
      expect(results[2].finalRank, 3);
    });

    test('dense ranking with skip for ties', () {
      final results = calc.compute(
        event: makeEvent(metric: RaceEventMetric.distance),
        participations: [
          makePart(userId: 'u1', totalDistanceM: 5000),
          makePart(userId: 'u2', totalDistanceM: 5000),
          makePart(userId: 'u3', totalDistanceM: 3000),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].finalRank, 1);
      expect(results[1].finalRank, 1);
      expect(results[2].finalRank, 3);
    });

    test('completers get full XP and coins', () {
      final results = calc.compute(
        event: makeEvent(xpReward: 100, coinsReward: 50),
        participations: [
          makePart(userId: 'u1', completed: true, sessionCount: 3),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].xpAwarded, 100);
      expect(results[0].coinsAwarded, 50);
    });

    test('participants get 20% participation XP, 0 coins', () {
      final results = calc.compute(
        event: makeEvent(xpReward: 100, coinsReward: 50),
        participations: [
          makePart(userId: 'u1', completed: false, sessionCount: 2),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].xpAwarded, 20);
      expect(results[0].coinsAwarded, 0);
    });

    test('zero-session athletes get 0 rewards', () {
      final results = calc.compute(
        event: makeEvent(xpReward: 100, coinsReward: 50),
        participations: [
          makePart(userId: 'u1', completed: false, sessionCount: 0),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].xpAwarded, 0);
      expect(results[0].coinsAwarded, 0);
    });

    test('badge is awarded only to completers', () {
      final results = calc.compute(
        event: makeEvent(badgeId: 'badge-10k'),
        participations: [
          makePart(userId: 'u1', completed: true, sessionCount: 1),
          makePart(userId: 'u2', completed: false, sessionCount: 1),
        ],
        idGenerator: idGen,
        nowMs: now,
      );

      expect(results[0].badgeId, 'badge-10k');
      expect(results[1].badgeId, isNull);
    });
  });
}
