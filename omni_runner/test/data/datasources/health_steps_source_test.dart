import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/data/datasources/health_steps_source.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeHealthProvider implements IHealthProvider {
  List<HealthStepSample> stepSamples;

  FakeHealthProvider({this.stepSamples = const []});

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async => true;
  @override
  Future<HealthFailure?> requestPermissions(
          List<HealthPermissionScope> scopes) async =>
      null;
  @override
  Future<List<HealthHrSample>> readHeartRate(
          {required DateTime start, required DateTime end}) async =>
      const [];
  @override
  Future<List<HealthStepSample>> readSteps(
      {required DateTime start, required DateTime end}) async {
    return stepSamples;
  }

  @override
  Future<int?> getTotalSteps(
          {required DateTime start, required DateTime end}) async =>
      null;
  @override
  Future<WorkoutExportResult> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    int? totalCalories,
    List<LocationPointEntity> route = const [],
    String? title,
  }) async =>
      const WorkoutExportResult(workoutSaved: true);
  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async =>
      samples.length;
  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async =>
      HealthConnectAvailability.notApplicable;
  @override
  Future<void> installHealthConnect() async {}
}

class FakeSessionRepo implements ISessionRepo {
  WorkoutSessionEntity? session;

  FakeSessionRepo({this.session});

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => session;
  @override
  Future<void> save(WorkoutSessionEntity session) async {}
  @override
  Future<List<WorkoutSessionEntity>> getAll() async => [];
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus status) async =>
      [];
  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async => true;
  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async =>
      true;
  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async =>
      true;
  @override
  Future<bool> updateIntegrityFlags(String id,
          {required bool isVerified, required List<String> flags}) async =>
      true;
  @override
  Future<void> deleteById(String id) async {}
  @override
  Future<bool> updateHrMetrics(String id,
          {required int avgBpm, required int maxBpm}) async =>
      true;
  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted() async => [];
  @override
  Future<void> markSynced(String id) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeHealthProvider fakeHealth;
  late FakeSessionRepo fakeSession;
  late HealthStepsSource sut;

  const session = WorkoutSessionEntity(
    id: 'session-1',
    status: WorkoutStatus.completed,
    startTimeMs: 1000000,
    endTimeMs: 1060000, // 60 seconds later
    route: [],
  );

  setUp(() {
    fakeHealth = FakeHealthProvider();
    fakeSession = FakeSessionRepo(session: session);
    sut = HealthStepsSource(
      provider: fakeHealth,
      sessionRepo: fakeSession,
    );
  });

  group('HealthStepsSource', () {
    test('returns empty list when session not found', () async {
      fakeSession.session = null;
      final result = await sut.samplesForSession('nonexistent');
      expect(result, isEmpty);
    });

    test('returns empty list when no step data', () async {
      fakeHealth.stepSamples = const [];
      final result = await sut.samplesForSession('session-1');
      expect(result, isEmpty);
    });

    test('converts HealthStepSample to StepSample with correct SPM', () async {
      fakeHealth.stepSamples = const [
        // 120 steps in 60 seconds = 120 SPM
        HealthStepSample(steps: 120, startMs: 1000000, endMs: 1060000),
      ];

      final result = await sut.samplesForSession('session-1');
      expect(result, hasLength(1));
      expect(result[0].spm, closeTo(120.0, 0.01));
      // Midpoint: 1000000 + (60000 / 2) = 1030000
      expect(result[0].timestampMs, 1030000);
    });

    test('converts multiple step windows correctly', () async {
      fakeHealth.stepSamples = const [
        // 60 steps in 30s = 120 SPM
        HealthStepSample(steps: 60, startMs: 1000000, endMs: 1030000),
        // 90 steps in 30s = 180 SPM
        HealthStepSample(steps: 90, startMs: 1030000, endMs: 1060000),
      ];

      final result = await sut.samplesForSession('session-1');
      expect(result, hasLength(2));
      expect(result[0].spm, closeTo(120.0, 0.01));
      expect(result[1].spm, closeTo(180.0, 0.01));
    });

    test('samples are sorted by timestamp', () async {
      fakeHealth.stepSamples = const [
        HealthStepSample(steps: 90, startMs: 1030000, endMs: 1060000),
        HealthStepSample(steps: 60, startMs: 1000000, endMs: 1030000),
      ];

      final result = await sut.samplesForSession('session-1');
      expect(result, hasLength(2));
      expect(result[0].timestampMs, lessThan(result[1].timestampMs));
    });

    test('skips samples with zero duration', () async {
      fakeHealth.stepSamples = const [
        HealthStepSample(steps: 100, startMs: 1000000, endMs: 1000000),
        HealthStepSample(steps: 60, startMs: 1000000, endMs: 1030000),
      ];

      final result = await sut.samplesForSession('session-1');
      expect(result, hasLength(1));
      expect(result[0].spm, closeTo(120.0, 0.01));
    });

    test('uses current time as end when session has no endTimeMs', () async {
      fakeSession.session = const WorkoutSessionEntity(
        id: 'session-active',
        status: WorkoutStatus.running,
        startTimeMs: 1000000,
        route: [],
      );
      fakeHealth.stepSamples = const [
        HealthStepSample(steps: 150, startMs: 1000000, endMs: 1060000),
      ];

      final result = await sut.samplesForSession('session-active');
      // Should still work — endMs derived from DateTime.now()
      expect(result, hasLength(1));
    });

    test('low cadence produces low SPM (vehicle suspect scenario)', () async {
      fakeHealth.stepSamples = const [
        // 10 steps in 60 seconds = 10 SPM (suspiciously low)
        HealthStepSample(steps: 10, startMs: 1000000, endMs: 1060000),
      ];

      final result = await sut.samplesForSession('session-1');
      expect(result, hasLength(1));
      expect(result[0].spm, closeTo(10.0, 0.01));
      expect(result[0].spm, lessThan(140.0),
          reason: 'below IntegrityDetectVehicle threshold');
    });
  });
}
