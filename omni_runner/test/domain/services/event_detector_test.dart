import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';
import 'package:omni_runner/domain/services/event_detector.dart';

void main() {
  const detector = EventDetector();

  RaceEventEntity makeEvent({
    String id = 'evt-1',
    int startsAtMs = 1000,
    int endsAtMs = 9000,
    double? targetDistanceM = 10000,
    RaceEventStatus status = RaceEventStatus.active,
  }) =>
      RaceEventEntity(
        id: id,
        groupId: 'g1',
        title: 'Test Race',
        metric: RaceEventMetric.distance,
        targetDistanceM: targetDistanceM,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        status: status,
        createdByUserId: 'coach',
        createdAtMs: 0,
        xpReward: 100,
        coinsReward: 50,
      );

  RaceParticipationEntity makePart({
    String eventId = 'evt-1',
    double totalDistanceM = 0,
    List<String> sessionIds = const [],
    bool completed = false,
  }) =>
      RaceParticipationEntity(
        id: 'part-1',
        raceEventId: eventId,
        userId: 'user-1',
        displayName: 'João',
        joinedAtMs: 500,
        totalDistanceM: totalDistanceM,
        contributingSessionIds: sessionIds,
        completed: completed,
      );

  const validSession = DetectableSession(
    sessionId: 'ses-1',
    userId: 'user-1',
    startTimeMs: 2000,
    endTimeMs: 3000,
    distanceM: 5000,
    movingMs: 1800000,
    avgPaceSecPerKm: 360,
  );

  group('EventDetector', () {
    test('returns empty when session is unverified', () {
      const unverified = DetectableSession(
        sessionId: 'ses-1',
        userId: 'user-1',
        startTimeMs: 2000,
        endTimeMs: 3000,
        distanceM: 5000,
        movingMs: 1800000,
        isVerified: false,
      );

      final matches = detector.detect(
        session: unverified,
        activeEvents: [makeEvent()],
        participations: {'evt-1': makePart()},
      );

      expect(matches, isEmpty);
    });

    test('returns empty when no events match time window', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent(startsAtMs: 5000, endsAtMs: 9000)],
        participations: {'evt-1': makePart()},
      );

      expect(matches, isEmpty);
    });

    test('returns empty when no participation exists', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent()],
        participations: {},
      );

      expect(matches, isEmpty);
    });

    test('returns empty when session already contributed', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent()],
        participations: {'evt-1': makePart(sessionIds: ['ses-1'])},
      );

      expect(matches, isEmpty);
    });

    test('detects matching event and accumulates distance', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent()],
        participations: {'evt-1': makePart(totalDistanceM: 3000)},
      );

      expect(matches, hasLength(1));
      expect(matches[0].updatedParticipation.totalDistanceM, 8000);
      expect(
        matches[0].updatedParticipation.contributingSessionIds,
        contains('ses-1'),
      );
      expect(matches[0].newlyCompleted, isFalse);
    });

    test('detects target completion', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent(targetDistanceM: 7000)],
        participations: {'evt-1': makePart(totalDistanceM: 3000)},
      );

      expect(matches, hasLength(1));
      expect(matches[0].newlyCompleted, isTrue);
      expect(matches[0].updatedParticipation.completed, isTrue);
      expect(matches[0].updatedParticipation.completedAtMs, 3000);
    });

    test('does not re-complete already completed participation', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent()],
        participations: {
          'evt-1': makePart(totalDistanceM: 15000, completed: true),
        },
      );

      expect(matches, hasLength(1));
      expect(matches[0].newlyCompleted, isFalse);
    });

    test('keeps best pace (lower is better)', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [makeEvent()],
        participations: {'evt-1': makePart()},
      );

      expect(matches[0].updatedParticipation.bestPaceSecPerKm, 360);
    });

    test('matches multiple events in same time window', () {
      final matches = detector.detect(
        session: validSession,
        activeEvents: [
          makeEvent(id: 'evt-1'),
          makeEvent(id: 'evt-2'),
        ],
        participations: {
          'evt-1': makePart(eventId: 'evt-1'),
          'evt-2': makePart(eventId: 'evt-2'),
        },
      );

      expect(matches, hasLength(2));
    });
  });
}
