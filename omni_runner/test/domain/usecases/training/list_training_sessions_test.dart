import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/usecases/training/list_training_sessions.dart';

TrainingSessionEntity _session(String id, String groupId) =>
    TrainingSessionEntity(
      id: id,
      groupId: groupId,
      createdBy: 'coach-1',
      title: 'Session $id',
      startsAt: DateTime(2026, 4, 1),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

class _FakeSessionRepo implements ITrainingSessionRepo {
  final List<TrainingSessionEntity> sessions = [];
  String? lastGroupId;
  DateTime? lastFrom;
  DateTime? lastTo;
  TrainingSessionStatus? lastStatus;
  int? lastLimit;
  int? lastOffset;

  @override
  Future<List<TrainingSessionEntity>> listByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    lastGroupId = groupId;
    lastFrom = from;
    lastTo = to;
    lastStatus = status;
    lastLimit = limit;
    lastOffset = offset;
    return sessions.where((s) => s.groupId == groupId).toList();
  }

  @override
  Future<TrainingSessionEntity> create(TrainingSessionEntity session) async =>
      session;
  @override
  Future<TrainingSessionEntity> update(TrainingSessionEntity session) async =>
      session;
  @override
  Future<TrainingSessionEntity?> getById(String id) async => null;
  @override
  Future<void> cancel(String sessionId) async {}
}

void main() {
  late _FakeSessionRepo repo;
  late ListTrainingSessions usecase;

  setUp(() {
    repo = _FakeSessionRepo();
    usecase = ListTrainingSessions(repo: repo);
  });

  test('returns empty list when no sessions exist', () async {
    final result = await usecase.call(groupId: 'group-1');
    expect(result, isEmpty);
  });

  test('returns sessions for a given group', () async {
    repo.sessions.addAll([
      _session('s1', 'group-1'),
      _session('s2', 'group-1'),
      _session('s3', 'group-2'),
    ]);

    final result = await usecase.call(groupId: 'group-1');
    expect(result.length, 2);
    expect(result.every((s) => s.groupId == 'group-1'), isTrue);
  });

  test('passes filter parameters to repo', () async {
    final from = DateTime(2026, 3, 1);
    final to = DateTime(2026, 4, 1);

    await usecase.call(
      groupId: 'group-1',
      from: from,
      to: to,
      status: TrainingSessionStatus.scheduled,
      limit: 10,
      offset: 5,
    );

    expect(repo.lastGroupId, 'group-1');
    expect(repo.lastFrom, from);
    expect(repo.lastTo, to);
    expect(repo.lastStatus, TrainingSessionStatus.scheduled);
    expect(repo.lastLimit, 10);
    expect(repo.lastOffset, 5);
  });

  test('uses default limit and offset', () async {
    await usecase.call(groupId: 'group-1');

    expect(repo.lastLimit, 50);
    expect(repo.lastOffset, 0);
  });
}
