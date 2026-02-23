import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/usecases/ensure_health_ready.dart';

/// Fake implementation of [IHealthProvider] for testing.
///
/// All responses are controllable. No platform dependency.
class FakeHealthProvider implements IHealthProvider {
  bool availableResult;
  bool hasPermissionsResult;
  HealthFailure? requestPermissionsResult;
  List<HealthHrSample> hrResult;
  List<HealthStepSample> stepsResult;
  int? totalStepsResult;

  int isAvailableCalls = 0;
  int hasPermissionsCalls = 0;
  int requestPermissionsCalls = 0;
  List<HealthPermissionScope> lastRequestedScopes = [];

  FakeHealthProvider({
    this.availableResult = true,
    this.hasPermissionsResult = true,
    this.requestPermissionsResult,
    this.hrResult = const [],
    this.stepsResult = const [],
    this.totalStepsResult,
  });

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls++;
    return availableResult;
  }

  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async {
    hasPermissionsCalls++;
    return hasPermissionsResult;
  }

  @override
  Future<HealthFailure?> requestPermissions(
    List<HealthPermissionScope> scopes,
  ) async {
    requestPermissionsCalls++;
    lastRequestedScopes = scopes;
    return requestPermissionsResult;
  }

  @override
  Future<List<HealthHrSample>> readHeartRate({
    required DateTime start,
    required DateTime end,
  }) async =>
      hrResult;

  @override
  Future<List<HealthStepSample>> readSteps({
    required DateTime start,
    required DateTime end,
  }) async =>
      stepsResult;

  @override
  Future<int?> getTotalSteps({
    required DateTime start,
    required DateTime end,
  }) async =>
      totalStepsResult;

  @override
  Future<WorkoutExportResult> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    int? totalCalories,
    List<LocationPointEntity> route = const [],
    String? title,
  }) async =>
      const WorkoutExportResult(workoutSaved: true, message: 'fake');

  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async =>
      samples.length;

  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async =>
      HealthConnectAvailability.notApplicable;

  @override
  Future<void> installHealthConnect() async {}
}

void main() {
  late FakeHealthProvider fake;
  late EnsureHealthReady sut;

  setUp(() {
    fake = FakeHealthProvider();
    sut = EnsureHealthReady(fake);
  });

  group('EnsureHealthReady', () {
    test('returns null when service available and permissions granted',
        () async {
      final result = await sut.call();
      expect(result, isNull);
      expect(fake.isAvailableCalls, 1);
      expect(fake.requestPermissionsCalls, 1);
    });

    test('returns HealthNotAvailable when service is not available', () async {
      fake.availableResult = false;

      final result = await sut.call();
      expect(result, isA<HealthNotAvailable>());
      expect(fake.isAvailableCalls, 1);
      expect(fake.requestPermissionsCalls, 0,
          reason: 'should not request permissions if unavailable');
    });

    test('returns HealthPermissionDenied when permissions denied', () async {
      fake.requestPermissionsResult = const HealthPermissionDenied();

      final result = await sut.call();
      expect(result, isA<HealthPermissionDenied>());
    });

    test('returns HealthUnknownError on unexpected failure', () async {
      fake.requestPermissionsResult =
          const HealthUnknownError('platform error');

      final result = await sut.call();
      expect(result, isA<HealthUnknownError>());
      expect((result as HealthUnknownError).message, 'platform error');
    });

    test('uses default scopes (readHeartRate + readSteps)', () async {
      await sut.call();
      expect(fake.lastRequestedScopes, [
        HealthPermissionScope.readHeartRate,
        HealthPermissionScope.readSteps,
      ]);
    });

    test('passes custom scopes correctly', () async {
      await sut.call(scopes: [
        HealthPermissionScope.readHeartRate,
        HealthPermissionScope.writeWorkout,
      ]);
      expect(fake.lastRequestedScopes, [
        HealthPermissionScope.readHeartRate,
        HealthPermissionScope.writeWorkout,
      ]);
    });

    test('does not check permissions when unavailable', () async {
      fake.availableResult = false;

      await sut.call();
      expect(fake.requestPermissionsCalls, 0);
      expect(fake.hasPermissionsCalls, 0);
    });
  });

  group('HealthFailure subtypes', () {
    test('all subtypes are distinct types', () {
      const failures = <HealthFailure>[
        HealthNotAvailable(),
        HealthPermissionDenied(),
        HealthPermissionPartial(grantedTypes: ['HR']),
        HealthUnknownError('test'),
      ];
      final types = failures.map((f) => f.runtimeType).toSet();
      expect(types.length, 4);
    });

    test('HealthPermissionPartial carries granted types', () {
      const partial =
          HealthPermissionPartial(grantedTypes: ['HEART_RATE', 'STEPS']);
      expect(partial.grantedTypes, ['HEART_RATE', 'STEPS']);
    });

    test('HealthPermissionPartial defaults to empty list', () {
      const partial = HealthPermissionPartial();
      expect(partial.grantedTypes, isEmpty);
    });

    test('HealthUnknownError carries message', () {
      const err = HealthUnknownError('something went wrong');
      expect(err.message, 'something went wrong');
    });
  });

  group('HealthConnectAvailability', () {
    test('all values are accessible', () {
      expect(HealthConnectAvailability.values, hasLength(4));
      expect(HealthConnectAvailability.values,
          contains(HealthConnectAvailability.available));
      expect(HealthConnectAvailability.values,
          contains(HealthConnectAvailability.needsUpdate));
      expect(HealthConnectAvailability.values,
          contains(HealthConnectAvailability.unavailable));
      expect(HealthConnectAvailability.values,
          contains(HealthConnectAvailability.notApplicable));
    });
  });

  group('EnsureHealthReady with ActivityRecognition', () {
    test('AR requester not called on non-Android platform', () async {
      // Tests run on Linux, not Android.
      int arCalls = 0;
      final sut = EnsureHealthReady(
        FakeHealthProvider(),
        requestActivityRecognition: () async {
          arCalls++;
          return PermissionStatusEntity.granted;
        },
      );

      await sut.call();
      if (Platform.isAndroid) {
        expect(arCalls, 1);
      } else {
        expect(arCalls, 0, reason: 'AR not requested on non-Android');
      }
    });

    test('works without AR requester (null)', () async {
      final sut = EnsureHealthReady(FakeHealthProvider());
      final result = await sut.call();
      expect(result, isNull);
    });
  });
}
