import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/usecases/training/cancel_training_session.dart';

class _FakeSessionRepo implements ITrainingSessionRepo {
  final List<String> cancelledIds = [];
  bool shouldThrow = false;

  @override
  Future<void> cancel(String sessionId) async {
    if (shouldThrow) throw Exception('Session not found');
    cancelledIds.add(sessionId);
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
  Future<List<TrainingSessionEntity>> listByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
}

void main() {
  late _FakeSessionRepo repo;
  late CancelTrainingSession usecase;

  setUp(() {
    repo = _FakeSessionRepo();
    usecase = CancelTrainingSession(repo: repo);
  });

  test('cancels a session by id', () async {
    await usecase.call(sessionId: 'sess-1');

    expect(repo.cancelledIds, contains('sess-1'));
  });

  test('cancels multiple sessions independently', () async {
    await usecase.call(sessionId: 'sess-1');
    await usecase.call(sessionId: 'sess-2');

    expect(repo.cancelledIds, ['sess-1', 'sess-2']);
  });

  test('propagates repo exceptions', () {
    repo.shouldThrow = true;

    expect(
      () => usecase.call(sessionId: 'sess-1'),
      throwsA(isA<Exception>()),
    );
  });
}
