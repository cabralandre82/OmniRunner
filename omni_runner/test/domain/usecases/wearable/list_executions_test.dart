import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';
import 'package:omni_runner/domain/usecases/wearable/list_executions.dart';

WorkoutExecutionEntity _execution(
        String id, String groupId, String athleteId) =>
    WorkoutExecutionEntity(
      id: id,
      groupId: groupId,
      athleteUserId: athleteId,
      source: 'manual',
      completedAt: DateTime(2026, 3, 15),
    );

class _FakeWearableRepo implements IWearableRepo {
  final List<WorkoutExecutionEntity> executions = [];
  String? lastGroupId;
  String? lastAthleteUserId;
  int? lastLimit;

  @override
  Future<List<WorkoutExecutionEntity>> listExecutions({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  }) async {
    lastGroupId = groupId;
    lastAthleteUserId = athleteUserId;
    lastLimit = limit;
    return executions
        .where(
            (e) => e.groupId == groupId && e.athleteUserId == athleteUserId)
        .take(limit)
        .toList();
  }

  @override
  Future<List<DeviceLinkEntity>> listDeviceLinks(
          String athleteUserId) async =>
      [];
  @override
  Future<DeviceLinkEntity> linkDevice({
    required String groupId,
    required String provider,
    String? accessToken,
    String? refreshToken,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> unlinkDevice(String linkId) async {}
  @override
  Future<Map<String, dynamic>> generateWorkoutPayload(
          String assignmentId) async =>
      {};
  @override
  Future<WorkoutExecutionEntity> importExecution({
    String? assignmentId,
    required int durationSeconds,
    int? distanceMeters,
    int? avgPace,
    int? avgHr,
    int? maxHr,
    int? calories,
    String source = 'manual',
    String? providerActivityId,
  }) async =>
      throw UnimplementedError();
}

void main() {
  late _FakeWearableRepo repo;
  late ListExecutions usecase;

  setUp(() {
    repo = _FakeWearableRepo();
    usecase = ListExecutions(repo: repo);
  });

  test('returns empty list when no executions exist', () async {
    final result = await usecase.call(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(result, isEmpty);
  });

  test('returns executions for given group and athlete', () async {
    repo.executions.addAll([
      _execution('e1', 'group-1', 'athlete-1'),
      _execution('e2', 'group-1', 'athlete-1'),
      _execution('e3', 'group-1', 'athlete-2'),
      _execution('e4', 'group-2', 'athlete-1'),
    ]);

    final result = await usecase.call(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(result.length, 2);
  });

  test('passes parameters to repo', () async {
    await usecase.call(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      limit: 10,
    );

    expect(repo.lastGroupId, 'group-1');
    expect(repo.lastAthleteUserId, 'athlete-1');
    expect(repo.lastLimit, 10);
  });

  test('uses default limit', () async {
    await usecase.call(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(repo.lastLimit, 50);
  });
}
