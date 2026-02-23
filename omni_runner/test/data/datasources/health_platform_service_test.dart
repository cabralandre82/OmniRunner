import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';

/// Tests for [IHealthProvider] contract compliance.
///
/// Uses the same [FakeHealthProvider] pattern to ensure the domain contract
/// is correctly defined and exercisable. The actual [HealthPlatformService]
/// wraps the `health` plugin which requires platform channels, so integration
/// tests must run on a real device.
///
/// These tests verify the contract + entity mapping logic at domain level.
class FakeHealthProvider implements IHealthProvider {
  bool availableResult;
  bool hasPermResult;
  HealthFailure? requestPermResult;
  List<HealthHrSample> hrSamples;
  List<HealthStepSample> stepSamples;
  int? totalSteps;

  WorkoutExportResult writeWorkoutResult;

  int readHrCalls = 0;
  int readStepsCalls = 0;
  int getTotalStepsCalls = 0;
  int writeWorkoutCalls = 0;
  DateTime? lastHrStart;
  DateTime? lastHrEnd;
  DateTime? lastStepsStart;
  DateTime? lastStepsEnd;
  DateTime? lastWorkoutStart;
  DateTime? lastWorkoutEnd;
  double? lastWorkoutDistance;
  List<LocationPointEntity>? lastWorkoutRoute;

  FakeHealthProvider({
    this.availableResult = true,
    this.hasPermResult = true,
    this.requestPermResult,
    this.hrSamples = const [],
    this.stepSamples = const [],
    this.totalSteps,
    this.writeWorkoutResult = const WorkoutExportResult(workoutSaved: true, message: 'fake'),
  });

  @override
  Future<bool> isAvailable() async => availableResult;
  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async =>
      hasPermResult;
  @override
  Future<HealthFailure?> requestPermissions(
          List<HealthPermissionScope> scopes) async =>
      requestPermResult;

  @override
  Future<List<HealthHrSample>> readHeartRate({
    required DateTime start,
    required DateTime end,
  }) async {
    readHrCalls++;
    lastHrStart = start;
    lastHrEnd = end;
    return hrSamples;
  }

  @override
  Future<List<HealthStepSample>> readSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    readStepsCalls++;
    lastStepsStart = start;
    lastStepsEnd = end;
    return stepSamples;
  }

  @override
  Future<int?> getTotalSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    getTotalStepsCalls++;
    return totalSteps;
  }

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
    lastWorkoutStart = start;
    lastWorkoutEnd = end;
    lastWorkoutDistance = totalDistanceM;
    lastWorkoutRoute = route;
    return writeWorkoutResult;
  }

  int writeHrSamplesCalls = 0;
  int lastWrittenHrCount = 0;
  int writeHrSamplesResult = 0;

  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async {
    writeHrSamplesCalls++;
    lastWrittenHrCount = samples.length;
    return writeHrSamplesResult;
  }

  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async =>
      HealthConnectAvailability.notApplicable;

  @override
  Future<void> installHealthConnect() async {}
}

void main() {
  group('IHealthProvider contract', () {
    late FakeHealthProvider provider;

    setUp(() {
      provider = FakeHealthProvider();
    });

    test('readHeartRate returns empty list by default', () async {
      final result = await provider.readHeartRate(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result, isEmpty);
      expect(provider.readHrCalls, 1);
    });

    test('readHeartRate returns configured samples', () async {
      provider.hrSamples = const [
        HealthHrSample(bpm: 72, startMs: 1000, endMs: 2000),
        HealthHrSample(bpm: 80, startMs: 3000, endMs: 4000),
      ];

      final result = await provider.readHeartRate(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result.length, 2);
      expect(result[0].bpm, 72);
      expect(result[1].bpm, 80);
    });

    test('readHeartRate passes time range correctly', () async {
      final start = DateTime(2025, 6, 15, 8, 0);
      final end = DateTime(2025, 6, 15, 9, 0);

      await provider.readHeartRate(start: start, end: end);
      expect(provider.lastHrStart, start);
      expect(provider.lastHrEnd, end);
    });

    test('readSteps returns empty list by default', () async {
      final result = await provider.readSteps(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result, isEmpty);
      expect(provider.readStepsCalls, 1);
    });

    test('readSteps returns configured samples', () async {
      provider.stepSamples = const [
        HealthStepSample(steps: 100, startMs: 1000, endMs: 60000),
        HealthStepSample(steps: 200, startMs: 60000, endMs: 120000),
      ];

      final result = await provider.readSteps(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result.length, 2);
      expect(result[0].steps, 100);
      expect(result[1].steps, 200);
    });

    test('readSteps passes time range correctly', () async {
      final start = DateTime(2025, 6, 15, 8, 0);
      final end = DateTime(2025, 6, 15, 9, 0);

      await provider.readSteps(start: start, end: end);
      expect(provider.lastStepsStart, start);
      expect(provider.lastStepsEnd, end);
    });

    test('getTotalSteps returns null by default', () async {
      final result = await provider.getTotalSteps(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result, isNull);
      expect(provider.getTotalStepsCalls, 1);
    });

    test('getTotalSteps returns configured value', () async {
      provider.totalSteps = 8500;

      final result = await provider.getTotalSteps(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
      );
      expect(result, 8500);
    });

    test('isAvailable returns configured result', () async {
      expect(await provider.isAvailable(), isTrue);
      provider.availableResult = false;
      expect(await provider.isAvailable(), isFalse);
    });

    test('hasPermissions returns configured result', () async {
      expect(
        await provider.hasPermissions([HealthPermissionScope.readHeartRate]),
        isTrue,
      );
      provider.hasPermResult = false;
      expect(
        await provider.hasPermissions([HealthPermissionScope.readSteps]),
        isFalse,
      );
    });

    test('requestPermissions returns null on success', () async {
      final result = await provider.requestPermissions([
        HealthPermissionScope.readHeartRate,
        HealthPermissionScope.readSteps,
      ]);
      expect(result, isNull);
    });

    test('requestPermissions returns failure on error', () async {
      provider.requestPermResult = const HealthPermissionDenied();
      final result = await provider.requestPermissions([
        HealthPermissionScope.readHeartRate,
      ]);
      expect(result, isA<HealthPermissionDenied>());
    });
  });

  group('writeWorkout contract', () {
    late FakeHealthProvider provider;

    setUp(() {
      provider = FakeHealthProvider();
    });

    test('writeWorkout returns success by default', () async {
      final result = await provider.writeWorkout(
        start: DateTime(2025, 6, 15, 8, 0),
        end: DateTime(2025, 6, 15, 9, 0),
        totalDistanceM: 5000,
      );
      expect(result.workoutSaved, isTrue);
      expect(provider.writeWorkoutCalls, 1);
    });

    test('writeWorkout passes parameters correctly', () async {
      final start = DateTime(2025, 6, 15, 8, 0);
      final end = DateTime(2025, 6, 15, 9, 0);
      const route = [
        LocationPointEntity(lat: -23.55, lng: -46.63, timestampMs: 1000),
        LocationPointEntity(lat: -23.56, lng: -46.64, timestampMs: 2000),
      ];

      await provider.writeWorkout(
        start: start,
        end: end,
        totalDistanceM: 5123.4,
        route: route,
      );
      expect(provider.lastWorkoutStart, start);
      expect(provider.lastWorkoutEnd, end);
      expect(provider.lastWorkoutDistance, 5123.4);
      expect(provider.lastWorkoutRoute, hasLength(2));
    });

    test('writeWorkout returns failure when configured', () async {
      provider.writeWorkoutResult = const WorkoutExportResult(
        workoutSaved: false,
        message: 'permission denied',
      );

      final result = await provider.writeWorkout(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
        totalDistanceM: 1000,
      );
      expect(result.workoutSaved, isFalse);
      expect(result.message, 'permission denied');
    });

    test('writeWorkout with route attached', () async {
      provider.writeWorkoutResult = const WorkoutExportResult(
        workoutSaved: true,
        routeAttached: true,
        routePointCount: 50,
        message: 'success',
      );

      final result = await provider.writeWorkout(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 2),
        totalDistanceM: 10000,
      );
      expect(result.workoutSaved, isTrue);
      expect(result.routeAttached, isTrue);
      expect(result.routePointCount, 50);
    });
  });

  group('HealthPermissionScope', () {
    test('all values are accessible', () {
      expect(HealthPermissionScope.values, hasLength(7));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.readHeartRate));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.readSteps));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.writeWorkout));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.writeHeartRate));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.writeDistance));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.writeExerciseRoute));
      expect(HealthPermissionScope.values, contains(HealthPermissionScope.writeCalories));
    });
  });

  group('writeHrSamples contract', () {
    late FakeHealthProvider provider;

    setUp(() {
      provider = FakeHealthProvider();
    });

    test('returns count of written samples', () async {
      provider.writeHrSamplesResult = 3;
      final count = await provider.writeHrSamples(const [
        HealthHrSample(bpm: 150, startMs: 1000, endMs: 1000),
        HealthHrSample(bpm: 155, startMs: 2000, endMs: 2000),
        HealthHrSample(bpm: 160, startMs: 3000, endMs: 3000),
      ]);
      expect(count, 3);
      expect(provider.writeHrSamplesCalls, 1);
      expect(provider.lastWrittenHrCount, 3);
    });

    test('returns 0 for empty samples list', () async {
      final count = await provider.writeHrSamples(const []);
      expect(count, 0);
    });
  });

  group('HR sample sorting contract', () {
    test('samples should be sortable by startMs', () {
      final samples = [
        const HealthHrSample(bpm: 72, startMs: 3000, endMs: 4000),
        const HealthHrSample(bpm: 80, startMs: 1000, endMs: 2000),
        const HealthHrSample(bpm: 65, startMs: 5000, endMs: 6000),
      ];
      samples.sort((a, b) => a.startMs.compareTo(b.startMs));

      expect(samples[0].bpm, 80);
      expect(samples[1].bpm, 72);
      expect(samples[2].bpm, 65);
    });
  });

  group('Step sample sorting contract', () {
    test('samples should be sortable by startMs', () {
      final samples = [
        const HealthStepSample(steps: 100, startMs: 60000, endMs: 120000),
        const HealthStepSample(steps: 200, startMs: 0, endMs: 60000),
        const HealthStepSample(steps: 150, startMs: 120000, endMs: 180000),
      ];
      samples.sort((a, b) => a.startMs.compareTo(b.startMs));

      expect(samples[0].steps, 200);
      expect(samples[1].steps, 100);
      expect(samples[2].steps, 150);
    });
  });
}
