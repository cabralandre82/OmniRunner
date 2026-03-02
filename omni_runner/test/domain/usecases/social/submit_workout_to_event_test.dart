import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';
import 'package:omni_runner/domain/usecases/social/submit_workout_to_event.dart';

final _event = EventEntity(
  id: 'ev-1', title: 'Race', metric: GoalMetric.distance,
  targetValue: 10000, startsAtMs: 0, endsAtMs: 999999,
  status: EventStatus.active, creatorUserId: 'admin',
  type: EventType.individual,
  rewards: const EventRewards(xpCompletion: 100),
);

class _FakeEventRepo implements IEventRepo {
  List<EventParticipationEntity> userParticipations = [];
  final List<EventParticipationEntity> _updated = [];

  @override Future<List<EventParticipationEntity>> getParticipationsByUser(String u) async => userParticipations;
  @override Future<EventEntity?> getEventById(String id) async => id == 'ev-1' ? _event : null;
  @override Future<void> updateParticipation(EventParticipationEntity p) async => _updated.add(p);
  @override Future<void> saveEvent(EventEntity e) async {}
  @override Future<void> updateEvent(EventEntity e) async {}
  @override Future<List<EventEntity>> getEventsByUserId(String u) async => [];
  @override Future<List<EventEntity>> getEventsByStatus(EventStatus s) async => [];
  @override Future<void> saveParticipation(EventParticipationEntity p) async {}
  @override Future<EventParticipationEntity?> getParticipation(String e, String u) async => null;
  @override Future<List<EventParticipationEntity>> getParticipationsByEvent(String e) async => [];
  @override Future<int> countParticipants(String e) async => 0;
}

void main() {
  late _FakeEventRepo repo;
  late SubmitWorkoutToEvent usecase;

  final session = WorkoutSessionEntity(
    id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
    startTimeMs: 100, route: const [], isVerified: true,
  );

  setUp(() {
    repo = _FakeEventRepo();
    usecase = SubmitWorkoutToEvent(eventRepo: repo);
  });

  test('adds distance to participation', () async {
    repo.userParticipations = [
      EventParticipationEntity(id: 'p1', eventId: 'ev-1', userId: 'u1', displayName: 'A', joinedAtMs: 0),
    ];

    final results = await usecase.call(
      session: session, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );

    expect(results, hasLength(1));
    expect(results.first.currentValue, 5000);
  });

  test('returns empty for unverified session', () async {
    final unverified = WorkoutSessionEntity(
      id: 'ses-2', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: const [], isVerified: false,
    );

    final results = await usecase.call(
      session: unverified, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );

    expect(results, isEmpty);
  });

  test('skips already completed participations', () async {
    repo.userParticipations = [
      EventParticipationEntity(
        id: 'p1', eventId: 'ev-1', userId: 'u1', displayName: 'A',
        joinedAtMs: 0, completed: true,
      ),
    ];

    final results = await usecase.call(
      session: session, totalDistanceM: 5000, movingMs: 1800000, nowMs: 500,
    );

    expect(results, isEmpty);
  });
}
