import 'package:health/health.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';

const String _tag = 'HealthService';

/// Concrete [IHealthProvider] backed by the `health` package.
///
/// Wraps HealthKit (iOS) and Health Connect (Android) behind a unified API.
/// All plugin-specific types are converted to domain entities at this layer.
class HealthPlatformService implements IHealthProvider {
  final Health _health;
  bool _configured = false;

  HealthPlatformService({Health? health}) : _health = health ?? Health();

  /// Call [Health.configure] once before any other API call.
  /// Sets internal device ID needed by the plugin.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _health.configure();
      _configured = true;
    } on Exception catch (e) {
      AppLogger.warn('Health.configure() failed: $e', tag: _tag);
    }
  }

  // ---------------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isAvailable() async {
    await _ensureConfigured();
    try {
      final status = await _health.getHealthConnectSdkStatus();
      // On iOS, getHealthConnectSdkStatus returns null — HealthKit is always
      // available on real devices. Check via hasPermissions returning non-error.
      // On Android, status must be HealthConnectSdkStatus.sdkAvailable.
      if (status != null) {
        return status == HealthConnectSdkStatus.sdkAvailable;
      }
      // iOS: HealthKit is available on real devices.
      return true;
    } on Exception catch (e) {
      AppLogger.warn('Health availability check failed: $e', tag: _tag);
      return false;
    }
  }

  @override
  Future<HealthConnectAvailability> getHealthConnectStatus() async {
    await _ensureConfigured();
    try {
      final status = await _health.getHealthConnectSdkStatus();
      if (status == null) {
        // iOS — not applicable.
        return HealthConnectAvailability.notApplicable;
      }
      return switch (status) {
        HealthConnectSdkStatus.sdkAvailable =>
          HealthConnectAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HealthConnectAvailability.needsUpdate,
        _ => HealthConnectAvailability.unavailable,
      };
    } on Exception catch (e) {
      AppLogger.warn('getHealthConnectStatus failed: $e', tag: _tag);
      return HealthConnectAvailability.unavailable;
    }
  }

  @override
  Future<void> installHealthConnect() async {
    try {
      await _health.installHealthConnect();
    } on Exception catch (e) {
      AppLogger.warn('installHealthConnect failed: $e', tag: _tag);
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes) async {
    await _ensureConfigured();
    try {
      final (types, accesses) = _mapScopes(scopes);
      final result = await _health.hasPermissions(types, permissions: accesses);
      // On iOS, result is null for READ permissions (privacy: Apple won't tell)
      return result ?? false;
    } on Exception catch (e) {
      AppLogger.warn('hasPermissions check failed: $e', tag: _tag);
      return false;
    }
  }

  @override
  Future<HealthFailure?> requestPermissions(
    List<HealthPermissionScope> scopes,
  ) async {
    await _ensureConfigured();
    try {
      final available = await isAvailable();
      if (!available) return const HealthNotAvailable();

      final (types, accesses) = _mapScopes(scopes);
      final authorized = await _health.requestAuthorization(
        types,
        permissions: accesses,
      );

      if (!authorized) {
        return const HealthPermissionDenied();
      }
      return null;
    } on Exception catch (e) {
      AppLogger.error('requestPermissions failed', tag: _tag, error: e);
      return HealthUnknownError(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Read Heart Rate
  // ---------------------------------------------------------------------------

  @override
  Future<List<HealthHrSample>> readHeartRate({
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureConfigured();
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );

      final samples = <HealthHrSample>[];
      for (final point in points) {
        final bpm = _numericValue(point);
        if (bpm == null || bpm <= 0) continue;
        samples.add(HealthHrSample(
          bpm: bpm.round(),
          startMs: point.dateFrom.millisecondsSinceEpoch,
          endMs: point.dateTo.millisecondsSinceEpoch,
        ));
      }

      samples.sort((a, b) => a.startMs.compareTo(b.startMs));
      return samples;
    } on Exception catch (e) {
      AppLogger.error('readHeartRate failed', tag: _tag, error: e);
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Read Steps
  // ---------------------------------------------------------------------------

  @override
  Future<List<HealthStepSample>> readSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureConfigured();
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );

      final samples = <HealthStepSample>[];
      for (final point in points) {
        final steps = _numericValue(point);
        if (steps == null || steps <= 0) continue;
        samples.add(HealthStepSample(
          steps: steps.round(),
          startMs: point.dateFrom.millisecondsSinceEpoch,
          endMs: point.dateTo.millisecondsSinceEpoch,
        ));
      }

      samples.sort((a, b) => a.startMs.compareTo(b.startMs));
      return samples;
    } on Exception catch (e) {
      AppLogger.error('readSteps failed', tag: _tag, error: e);
      return const [];
    }
  }

  @override
  Future<int?> getTotalSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureConfigured();
    try {
      return await _health.getTotalStepsInInterval(start, end);
    } on Exception catch (e) {
      AppLogger.error('getTotalSteps failed', tag: _tag, error: e);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Write Workout
  // ---------------------------------------------------------------------------

  @override
  Future<WorkoutExportResult> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    int? totalCalories,
    List<LocationPointEntity> route = const [],
    String? title,
  }) async {
    await _ensureConfigured();
    try {
      // 1. Write the HKWorkout / Health Connect exercise record.
      final saved = await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.RUNNING,
        start: start,
        end: end,
        totalDistance: totalDistanceM.round(),
        totalDistanceUnit: HealthDataUnit.METER,
        totalEnergyBurned: totalCalories,
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
        title: title ?? 'Omni Runner',
      );

      if (!saved) {
        return const WorkoutExportResult(
          workoutSaved: false,
          message: 'Health plugin returned false for writeWorkoutData',
        );
      }

      AppLogger.info(
        'Workout saved to Health: ${start.toIso8601String()} – '
        '${end.toIso8601String()}, ${totalDistanceM.round()}m',
        tag: _tag,
      );

      // 2. Attempt to attach GPS route.
      if (route.isEmpty) {
        return const WorkoutExportResult(
          workoutSaved: true,
          message: 'Workout saved. No route to attach (0 GPS points).',
        );
      }

      final routeResult = await _attachRoute(start, end, route);
      return routeResult;
    } on Exception catch (e, st) {
      AppLogger.error('writeWorkout failed', tag: _tag, error: e, stack: st);
      return WorkoutExportResult(
        workoutSaved: false,
        message: 'Exception: $e',
      );
    }
  }

  /// Attach GPS route to the most recently written workout.
  ///
  /// Flow:
  /// 1. Query WORKOUT type for the exact time window to get the UUID.
  /// 2. Start a route builder via `startWorkoutRoute`.
  /// 3. Insert all GPS points as `WorkoutRouteLocation`.
  /// 4. Finish the route, associating it with the workout UUID.
  Future<WorkoutExportResult> _attachRoute(
    DateTime start,
    DateTime end,
    List<LocationPointEntity> route,
  ) async {
    // Step 1: Retrieve the UUID of the workout we just wrote.
    String? workoutUuid;
    try {
      final workouts = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start.subtract(const Duration(seconds: 1)),
        endTime: end.add(const Duration(seconds: 1)),
      );

      if (workouts.isNotEmpty) {
        // Find the workout closest to our start/end time.
        workoutUuid = workouts.last.uuid;
      }
    } on Exception catch (e) {
      AppLogger.warn('Could not query workout UUID: $e', tag: _tag);
    }

    if (workoutUuid == null || workoutUuid.isEmpty) {
      AppLogger.warn(
        'Workout saved but UUID not retrievable — route not attached',
        tag: _tag,
      );
      return WorkoutExportResult(
        workoutSaved: true,
        routePointCount: route.length,
        message: 'Workout saved. Route skipped: '
            'could not retrieve workout UUID (health plugin limitation).',
      );
    }

    // Step 2-4: Build and attach route.
    String? builderId;
    try {
      builderId = await _health.startWorkoutRoute();
    } on Exception catch (e) {
      AppLogger.warn('startWorkoutRoute failed: $e', tag: _tag);
      return WorkoutExportResult(
        workoutSaved: true,
        routePointCount: route.length,
        message: 'Workout saved. Route skipped: startWorkoutRoute failed ($e).',
      );
    }

    try {
      final locations = route.map(_toRouteLocation).toList();

      // Insert in batches of 100 to avoid platform memory pressure.
      const batchSize = 100;
      for (var i = 0; i < locations.length; i += batchSize) {
        final end = (i + batchSize < locations.length)
            ? i + batchSize
            : locations.length;
        final batch = locations.sublist(i, end);
        final inserted = await _health.insertWorkoutRouteData(
          builderId: builderId,
          locations: batch,
        );
        if (!inserted) {
          AppLogger.warn(
            'insertWorkoutRouteData returned false at batch $i',
            tag: _tag,
          );
        }
      }

      final routeUuid = await _health.finishWorkoutRoute(
        builderId: builderId,
        workoutUuid: workoutUuid,
      );

      AppLogger.info(
        'Route attached: $routeUuid (${route.length} points)',
        tag: _tag,
      );

      return WorkoutExportResult(
        workoutSaved: true,
        routeAttached: true,
        routePointCount: route.length,
        message: 'Workout + route exported successfully.',
      );
    } on Exception catch (e, st) {
      AppLogger.error('Route attachment failed', tag: _tag, error: e, stack: st);

      // Attempt to discard the route builder to avoid leaks.
      try {
        await _health.discardWorkoutRoute(builderId);
      } on Exception catch (_) {
        // Best effort cleanup.
      }

      return WorkoutExportResult(
        workoutSaved: true,
        routePointCount: route.length,
        message: 'Workout saved. Route failed: $e',
      );
    }
  }

  /// Convert a domain [LocationPointEntity] to a `health` package
  /// [WorkoutRouteLocation].
  static WorkoutRouteLocation _toRouteLocation(LocationPointEntity pt) {
    return WorkoutRouteLocation(
      latitude: pt.lat,
      longitude: pt.lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(pt.timestampMs, isUtc: true),
      altitude: pt.alt,
      horizontalAccuracy: pt.accuracy,
      speed: pt.speed,
      course: pt.bearing,
    );
  }

  // ---------------------------------------------------------------------------
  // Write HR Samples
  // ---------------------------------------------------------------------------

  @override
  Future<int> writeHrSamples(List<HealthHrSample> samples) async {
    if (samples.isEmpty) return 0;
    await _ensureConfigured();

    int written = 0;
    for (final sample in samples) {
      try {
        final start = DateTime.fromMillisecondsSinceEpoch(
          sample.startMs,
          isUtc: true,
        );
        final end = DateTime.fromMillisecondsSinceEpoch(
          sample.endMs,
          isUtc: true,
        );
        final ok = await _health.writeHealthData(
          value: sample.bpm.toDouble(),
          type: HealthDataType.HEART_RATE,
          startTime: start,
          endTime: end,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
        );
        if (ok) written++;
      } on Exception catch (e) {
        AppLogger.warn('writeHrSample failed for bpm=${sample.bpm}: $e',
            tag: _tag);
      }
    }

    AppLogger.info(
      'Wrote $written / ${samples.length} HR samples to Health',
      tag: _tag,
    );
    return written;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Extract numeric value from a [HealthDataPoint].
  static num? _numericValue(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) {
      return value.numericValue;
    }
    return null;
  }

  /// Convert domain [HealthPermissionScope] list to `health` package types.
  static (List<HealthDataType>, List<HealthDataAccess>) _mapScopes(
    List<HealthPermissionScope> scopes,
  ) {
    final types = <HealthDataType>[];
    final accesses = <HealthDataAccess>[];

    for (final scope in scopes) {
      switch (scope) {
        case HealthPermissionScope.readHeartRate:
          types.add(HealthDataType.HEART_RATE);
          accesses.add(HealthDataAccess.READ);
        case HealthPermissionScope.readSteps:
          types.add(HealthDataType.STEPS);
          accesses.add(HealthDataAccess.READ);
        case HealthPermissionScope.writeWorkout:
          types.add(HealthDataType.WORKOUT);
          accesses.add(HealthDataAccess.WRITE);
        case HealthPermissionScope.writeHeartRate:
          types.add(HealthDataType.HEART_RATE);
          accesses.add(HealthDataAccess.WRITE);
        case HealthPermissionScope.writeDistance:
          types.add(HealthDataType.DISTANCE_DELTA);
          accesses.add(HealthDataAccess.WRITE);
        case HealthPermissionScope.writeExerciseRoute:
          types.add(HealthDataType.WORKOUT_ROUTE);
          accesses.add(HealthDataAccess.WRITE);
        case HealthPermissionScope.writeCalories:
          types.add(HealthDataType.TOTAL_CALORIES_BURNED);
          accesses.add(HealthDataAccess.WRITE);
      }
    }

    return (types, accesses);
  }
}
