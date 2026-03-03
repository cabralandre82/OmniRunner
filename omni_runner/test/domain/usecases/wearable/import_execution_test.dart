import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';
import 'package:omni_runner/domain/usecases/wearable/import_execution.dart';

class _FakeWearableRepo implements IWearableRepo {
  WorkoutExecutionEntity? lastImported;

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
  }) async {
    final exec = WorkoutExecutionEntity(
      id: 'exec-1',
      groupId: 'group-1',
      assignmentId: assignmentId,
      athleteUserId: 'athlete-1',
      actualDurationSeconds: durationSeconds,
      actualDistanceMeters: distanceMeters,
      avgPace: avgPace,
      avgHr: avgHr,
      maxHr: maxHr,
      calories: calories,
      source: source,
      completedAt: DateTime.now(),
    );
    lastImported = exec;
    return exec;
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
  Future<List<WorkoutExecutionEntity>> listExecutions({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  }) async =>
      [];
}

void main() {
  late _FakeWearableRepo repo;
  late ImportExecution usecase;

  setUp(() {
    repo = _FakeWearableRepo();
    usecase = ImportExecution(repo: repo);
  });

  test('imports execution with full data', () async {
    final result = await usecase.call(
      assignmentId: 'assign-1',
      durationSeconds: 1800,
      distanceMeters: 5000,
      avgPace: 360,
      avgHr: 155,
      maxHr: 175,
      calories: 400,
      source: 'garmin',
      providerActivityId: 'garmin-123',
    );

    expect(result.actualDurationSeconds, 1800);
    expect(result.actualDistanceMeters, 5000);
    expect(result.source, 'garmin');
    expect(result.assignmentId, 'assign-1');
    expect(repo.lastImported, isNotNull);
  });

  test('imports execution with minimal data', () async {
    final result = await usecase.call(
      durationSeconds: 600,
    );

    expect(result.actualDurationSeconds, 600);
    expect(result.source, 'manual');
    expect(result.assignmentId, isNull);
    expect(result.actualDistanceMeters, isNull);
  });

  test('imports execution without assignment', () async {
    final result = await usecase.call(
      durationSeconds: 3600,
      distanceMeters: 10000,
      source: 'apple',
    );

    expect(result.assignmentId, isNull);
    expect(result.actualDistanceMeters, 10000);
    expect(result.source, 'apple');
  });
}
