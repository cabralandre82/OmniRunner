import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/usecases/training/create_training_session.dart';

class _FakeSessionRepo implements ITrainingSessionRepo {
  TrainingSessionEntity? saved;

  @override
  Future<TrainingSessionEntity> create(TrainingSessionEntity session) async {
    saved = session;
    return session;
  }

  @override
  Future<TrainingSessionEntity> update(TrainingSessionEntity session) async =>
      session;
  @override
  Future<TrainingSessionEntity?> getById(String id) async => null;
  @override
  Future<List<TrainingSessionEntity>> listByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<void> cancel(String sessionId) async {}
}

void main() {
  late _FakeSessionRepo repo;
  late CreateTrainingSession usecase;

  setUp(() {
    repo = _FakeSessionRepo();
    usecase = CreateTrainingSession(repo: repo);
  });

  test('creates session with valid data', () async {
    final startsAt = DateTime(2026, 4, 1, 8, 0);
    final endsAt = DateTime(2026, 4, 1, 9, 0);

    final result = await usecase.call(
      id: 'sess-1',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Morning Run',
      description: 'Easy 5k',
      startsAt: startsAt,
      endsAt: endsAt,
      locationName: 'Ibirapuera Park',
      locationLat: -23.58,
      locationLng: -46.65,
    );

    expect(result.id, 'sess-1');
    expect(result.groupId, 'group-1');
    expect(result.title, 'Morning Run');
    expect(result.description, 'Easy 5k');
    expect(result.startsAt, startsAt);
    expect(result.endsAt, endsAt);
    expect(result.locationName, 'Ibirapuera Park');
    expect(repo.saved, isNotNull);
  });

  test('creates session without optional fields', () async {
    final startsAt = DateTime(2026, 4, 1, 8, 0);

    final result = await usecase.call(
      id: 'sess-2',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Intervals',
      startsAt: startsAt,
    );

    expect(result.endsAt, isNull);
    expect(result.description, isNull);
    expect(result.locationName, isNull);
    expect(result.status, TrainingSessionStatus.scheduled);
  });

  test('trims whitespace from title', () async {
    final result = await usecase.call(
      id: 'sess-3',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: '  Speed Work  ',
      startsAt: DateTime(2026, 5, 1),
    );

    expect(result.title, 'Speed Work');
  });

  test('throws when title is too short', () {
    expect(
      () => usecase.call(
        id: 'sess-4',
        groupId: 'group-1',
        createdBy: 'coach-1',
        title: 'A',
        startsAt: DateTime(2026, 4, 1),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when title is only whitespace', () {
    expect(
      () => usecase.call(
        id: 'sess-5',
        groupId: 'group-1',
        createdBy: 'coach-1',
        title: '   ',
        startsAt: DateTime(2026, 4, 1),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when endsAt is before startsAt', () {
    expect(
      () => usecase.call(
        id: 'sess-6',
        groupId: 'group-1',
        createdBy: 'coach-1',
        title: 'Run',
        startsAt: DateTime(2026, 4, 1, 10, 0),
        endsAt: DateTime(2026, 4, 1, 8, 0),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('allows endsAt equal to startsAt', () async {
    final dt = DateTime(2026, 4, 1, 10, 0);
    final result = await usecase.call(
      id: 'sess-7',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Quick',
      startsAt: dt,
      endsAt: dt,
    );

    expect(result.endsAt, dt);
  });

  test('creates session with workout params', () async {
    final result = await usecase.call(
      id: 'sess-8',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Treino de 5km',
      startsAt: DateTime(2026, 4, 1, 8, 0),
      distanceTargetM: 5000,
      paceMinSecKm: 270,
      paceMaxSecKm: 360,
    );

    expect(result.distanceTargetM, 5000);
    expect(result.paceMinSecKm, 270);
    expect(result.paceMaxSecKm, 360);
    expect(repo.saved!.distanceTargetM, 5000);
  });

  test('creates session without workout params', () async {
    final result = await usecase.call(
      id: 'sess-9',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Treino livre',
      startsAt: DateTime(2026, 4, 1, 8, 0),
    );

    expect(result.distanceTargetM, isNull);
    expect(result.paceMinSecKm, isNull);
    expect(result.paceMaxSecKm, isNull);
  });

  test('creates session with distance but no pace', () async {
    final result = await usecase.call(
      id: 'sess-10',
      groupId: 'group-1',
      createdBy: 'coach-1',
      title: 'Corrida leve',
      startsAt: DateTime(2026, 4, 1, 8, 0),
      distanceTargetM: 10000,
    );

    expect(result.distanceTargetM, 10000);
    expect(result.paceMinSecKm, isNull);
    expect(result.paceMaxSecKm, isNull);
  });
}
