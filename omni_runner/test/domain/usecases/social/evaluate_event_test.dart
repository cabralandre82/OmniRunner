import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';
import 'package:omni_runner/domain/usecases/social/evaluate_event.dart';

final _activeEvent = EventEntity(
  id: 'ev-1', title: 'Race', metric: GoalMetric.distance,
  targetValue: 10000, startsAtMs: 0, endsAtMs: 5000,
  status: EventStatus.active, creatorUserId: 'admin',
  type: EventType.individual,
  rewards: const EventRewards(xpCompletion: 100, xpParticipation: 20),
);

class _FakeEventRepo implements IEventRepo {
  EventEntity? event;
  List<EventParticipationEntity> participations = [];
  EventEntity? updatedEvent;
  final List<EventParticipationEntity> _updatedParts = [];

  @override Future<EventEntity?> getEventById(String id) async => event;
  @override Future<List<EventParticipationEntity>> getParticipationsByEvent(String e) async => participations;
  @override Future<void> updateEvent(EventEntity e) async => updatedEvent = e;
  @override Future<void> updateParticipation(EventParticipationEntity p) async => _updatedParts.add(p);
  @override Future<void> saveEvent(EventEntity e) async {}
  @override Future<List<EventEntity>> getEventsByUserId(String u) async => [];
  @override Future<List<EventEntity>> getEventsByStatus(EventStatus s) async => [];
  @override Future<void> saveParticipation(EventParticipationEntity p) async {}
  @override Future<EventParticipationEntity?> getParticipation(String e, String u) async => null;
  @override Future<List<EventParticipationEntity>> getParticipationsByUser(String u) async => [];
  @override Future<int> countParticipants(String e) async => 0;
}

void main() {
  late _FakeEventRepo repo;
  late EvaluateEvent usecase;

  setUp(() {
    repo = _FakeEventRepo()..event = _activeEvent;
    usecase = EvaluateEvent(eventRepo: repo);
  });

  test('evaluates event and transitions to completed', () async {
    repo.participations = [
      EventParticipationEntity(
        id: 'p1', eventId: 'ev-1', userId: 'u1', displayName: 'A',
        joinedAtMs: 0, currentValue: 12000, completed: true, contributingSessionCount: 3,
      ),
      EventParticipationEntity(
        id: 'p2', eventId: 'ev-1', userId: 'u2', displayName: 'B',
        joinedAtMs: 0, currentValue: 5000, contributingSessionCount: 1,
      ),
    ];

    final result = await usecase.call(eventId: 'ev-1', nowMs: 6000);
    expect(result.completers, hasLength(1));
    expect(result.participants, hasLength(1));
    expect(result.ranked, hasLength(2));
    expect(repo.updatedEvent!.status, EventStatus.completed);
  });

  test('throws when event not found', () {
    repo.event = null;
    expect(
      () => usecase.call(eventId: 'x', nowMs: 6000),
      throwsA(isA<EventNotFound>()),
    );
  });
}
