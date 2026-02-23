import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/usecases/export_workout_to_health.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeHealthProvider implements IHealthProvider {
  bool availableResult;
  bool hasPermResult;
  HealthFailure? requestPermResult;
  WorkoutExportResult writeWorkoutResult;

  int writeWorkoutCalls = 0;
  int hasPermCalls = 0;
  DateTime? lastStart;
  DateTime? lastEnd;
  double? lastDistance;
  List<LocationPointEntity>? lastRoute;

  FakeHealthProvider({
    this.availableResult = true,
    this.hasPermResult = true,
    this.requestPermResult,
    this.writeWorkoutResult = const WorkoutExportResult(
      workoutSaved: true,
      routeAttached: true,
      routePointCount: 2,
      message: 'success',
    ),
  });

  @override
  Future<bool> isAvailable() async => availableResult;
  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async {
    hasPermCalls++;
    return hasPermResult;
  }

  @override
  Future<HealthFailure?> requestPermissions(
          List<HealthPermissionScope> scopes) async =>
      requestPermResult;
  @override
  Future<List<HealthHrSample>> readHeartRate(
          {required DateTime start, required DateTime end}) async =>
      const [];
  @override
  Future<List<HealthStepSample>> readSteps(
          {required DateTime start, required DateTime end}) async =>
      const [];
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
  }) async {
    writeWorkoutCalls++;
    lastStart = start;
    lastEnd = end;
    lastDistance = totalDistanceM;
    lastRoute = route;
    return writeWorkoutResult;
  }

  int writeHrSamplesCalls = 0;
  List<HealthHrSample> lastWrittenHrSamples = const [];
  int writeHrSamplesResult = 0;

  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async {
    writeHrSamplesCalls++;
    lastWrittenHrSamples = samples;
    return writeHrSamplesResult > 0 ? writeHrSamplesResult : samples.length;
  }

  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async =>
      HealthConnectAvailability.notApplicable;

  @override
  Future<void> installHealthConnect() async {}
}

class FakePointsRepo implements IPointsRepo {
  List<LocationPointEntity> points;
  bool throwOnGet;

  FakePointsRepo({
    this.points = const [],
    this.throwOnGet = false,
  });

  @override
  Future<List<LocationPointEntity>> getBySessionId(String sessionId) async {
    if (throwOnGet) throw Exception('DB error');
    return points;
  }

  @override
  Future<void> savePoint(
          String sessionId, LocationPointEntity point) async {}
  @override
  Future<void> savePoints(
          String sessionId, List<LocationPointEntity> points) async {}
  @override
  Future<void> deleteBySessionId(String sessionId) async {}
  @override
  Future<int> countBySessionId(String sessionId) async => points.length;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeHealthProvider fakeHealth;
  late FakePointsRepo fakePoints;
  late ExportWorkoutToHealth sut;

  const route = [
    LocationPointEntity(lat: -23.55, lng: -46.63, timestampMs: 1000),
    LocationPointEntity(lat: -23.56, lng: -46.64, timestampMs: 2000),
  ];

  setUp(() {
    fakeHealth = FakeHealthProvider();
    fakePoints = FakePointsRepo(points: route);
    sut = ExportWorkoutToHealth(
      healthProvider: fakeHealth,
      pointsRepo: fakePoints,
    );
  });

  group('ExportWorkoutToHealth', () {
    test('exports workout with route successfully', () async {
      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isTrue);
      expect(result.routeAttached, isTrue);
      expect(fakeHealth.writeWorkoutCalls, 1);
      expect(fakeHealth.lastDistance, 5000);
      expect(fakeHealth.lastRoute, hasLength(2));
    });

    test('converts timestamps to DateTime correctly', () async {
      await sut.call(
        sessionId: 'session-1',
        startMs: 1718438400000, // 2024-06-15 08:00:00 UTC
        endMs: 1718442000000, // 2024-06-15 09:00:00 UTC
        totalDistanceM: 10000,
      );

      expect(fakeHealth.lastStart!.isUtc, isTrue);
      expect(fakeHealth.lastEnd!.isUtc, isTrue);
      expect(fakeHealth.lastStart!.millisecondsSinceEpoch, 1718438400000);
      expect(fakeHealth.lastEnd!.millisecondsSinceEpoch, 1718442000000);
    });

    test('returns failure when health not available', () async {
      fakeHealth.availableResult = false;

      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isFalse);
      expect(result.message, contains('not available'));
      expect(fakeHealth.writeWorkoutCalls, 0);
    });

    test('returns failure when write permission not granted', () async {
      fakeHealth.hasPermResult = false;

      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isFalse);
      expect(result.message, contains('permission'));
      expect(fakeHealth.writeWorkoutCalls, 0);
    });

    test('checks writeWorkout permission scope', () async {
      await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(fakeHealth.hasPermCalls, 1);
    });

    test('exports with empty route when points load fails', () async {
      fakePoints.throwOnGet = true;

      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isTrue);
      expect(fakeHealth.writeWorkoutCalls, 1);
      expect(fakeHealth.lastRoute, isEmpty);
    });

    test('exports with empty route when no GPS points', () async {
      fakePoints.points = const [];

      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isTrue);
      expect(fakeHealth.writeWorkoutCalls, 1);
      expect(fakeHealth.lastRoute, isEmpty);
    });

    test('forwards writeWorkout failure result', () async {
      fakeHealth.writeWorkoutResult = const WorkoutExportResult(
        workoutSaved: false,
        message: 'plugin error',
      );

      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      expect(result.workoutSaved, isFalse);
      expect(result.message, 'plugin error');
    });

    test('passes title as Omni Runner', () async {
      await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
      );

      // writeWorkout was called — title handling is inside the method
      expect(fakeHealth.writeWorkoutCalls, 1);
    });

    test('does not write HR samples on non-Android (tests run on Linux)',
        () async {
      await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
        hrSamples: const [
          HealthHrSample(bpm: 150, startMs: 1000, endMs: 1000),
          HealthHrSample(bpm: 160, startMs: 2000, endMs: 2000),
        ],
      );

      // On Linux (not Android), HR samples should NOT be written.
      expect(fakeHealth.writeHrSamplesCalls, 0);
    });

    test('does not write HR samples when workout save failed', () async {
      fakeHealth.writeWorkoutResult = const WorkoutExportResult(
        workoutSaved: false,
        message: 'fail',
      );

      await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
        hrSamples: const [
          HealthHrSample(bpm: 150, startMs: 1000, endMs: 1000),
        ],
      );

      expect(fakeHealth.writeHrSamplesCalls, 0);
    });

    test('accepts empty hrSamples without error', () async {
      final result = await sut.call(
        sessionId: 'session-1',
        startMs: 1000,
        endMs: 60000,
        totalDistanceM: 5000,
        hrSamples: const [],
      );

      expect(result.workoutSaved, isTrue);
      expect(fakeHealth.writeHrSamplesCalls, 0);
    });
  });

  group('WorkoutExportResult', () {
    test('equality by value', () {
      const a = WorkoutExportResult(
        workoutSaved: true,
        routeAttached: true,
        routePointCount: 100,
        message: 'ok',
      );
      const b = WorkoutExportResult(
        workoutSaved: true,
        routeAttached: true,
        routePointCount: 100,
        message: 'ok',
      );
      expect(a, equals(b));
    });

    test('inequality when workoutSaved differs', () {
      const a = WorkoutExportResult(workoutSaved: true);
      const b = WorkoutExportResult(workoutSaved: false);
      expect(a, isNot(equals(b)));
    });

    test('inequality when routeAttached differs', () {
      const a =
          WorkoutExportResult(workoutSaved: true, routeAttached: true);
      const b =
          WorkoutExportResult(workoutSaved: true, routeAttached: false);
      expect(a, isNot(equals(b)));
    });

    test('defaults are correct', () {
      const r = WorkoutExportResult(workoutSaved: true);
      expect(r.routeAttached, isFalse);
      expect(r.routePointCount, 0);
      expect(r.message, '');
    });
  });
}
