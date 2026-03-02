import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';
import 'package:omni_runner/domain/usecases/social/join_event.dart';

final _event = EventEntity(
  id: 'ev-1', title: 'Corrida Virtual', metric: GoalMetric.distance,
  targetValue: 42195, startsAtMs: 0, endsAtMs: 999999,
  status: EventStatus.active, creatorUserId: 'admin',
  type: EventType.individual,
  rewards: const EventRewards(xpCompletion: 100),
);

class _FakeEventRepo implements IEventRepo {
  EventParticipationEntity? existing;
  int participantCount = 0;
  List<EventParticipationEntity> userParticipations = [];
  EventParticipationEntity? saved;

  @override Future<EventEntity?> getEventById(String id) async => id == 'ev-1' ? _event : null;
  @override Future<EventParticipationEntity?> getParticipation(String e, String u) async => existing;
  @override Future<int> countParticipants(String e) async => participantCount;
  @override Future<List<EventParticipationEntity>> getParticipationsByUser(String u) async => userParticipations;
  @override Future<void> saveParticipation(EventParticipationEntity p) async => saved = p;
  @override Future<void> saveEvent(EventEntity e) async {}
  @override Future<void> updateEvent(EventEntity e) async {}
  @override Future<List<EventEntity>> getEventsByUserId(String u) async => [];
  @override Future<List<EventEntity>> getEventsByStatus(EventStatus s) async => [];
  @override Future<void> updateParticipation(EventParticipationEntity p) async {}
  @override Future<List<EventParticipationEntity>> getParticipationsByEvent(String e) async => [];
}

void main() {
  late _FakeEventRepo repo;
  late JoinEvent usecase;

  setUp(() {
    repo = _FakeEventRepo();
    usecase = JoinEvent(eventRepo: repo);
  });

  test('joins active event', () async {
    final p = await usecase.call(
      eventId: 'ev-1', userId: 'u1', displayName: 'Ana',
      uuidGenerator: () => 'p-id', nowMs: 1000,
    );
    expect(p.eventId, 'ev-1');
    expect(repo.saved, isNotNull);
  });

  test('throws when event not found', () {
    expect(
      () => usecase.call(eventId: 'x', userId: 'u1', displayName: 'A', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<EventNotFound>()),
    );
  });

  test('throws when already joined', () {
    repo.existing = EventParticipationEntity(id: 'p1', eventId: 'ev-1', userId: 'u1', displayName: 'A', joinedAtMs: 0);
    expect(
      () => usecase.call(eventId: 'ev-1', userId: 'u1', displayName: 'A', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<AlreadyJoinedEvent>()),
    );
  });

  test('throws when user has 5 active events', () {
    repo.userParticipations = List.generate(5, (i) =>
      EventParticipationEntity(id: 'p$i', eventId: 'e$i', userId: 'u1', displayName: 'A', joinedAtMs: 0),
    );
    expect(
      () => usecase.call(eventId: 'ev-1', userId: 'u1', displayName: 'A', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<EventLimitReached>()),
    );
  });
}
