import 'dart:io' show Platform;

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';

const String _tag = 'ExportWorkoutToHealth';

/// Permission scopes required for a full workout export.
///
/// On Android, Health Connect requires separate permissions for exercise,
/// distance, exercise route, and HR data. On iOS, [writeWorkout] alone
/// covers the HKWorkout record.
const _exportScopes = [
  HealthPermissionScope.writeWorkout,
  HealthPermissionScope.writeDistance,
  HealthPermissionScope.writeExerciseRoute,
  HealthPermissionScope.writeHeartRate,
];

/// Exports a completed workout to the platform health service
/// (HealthKit on iOS, Health Connect on Android).
///
/// Orchestration flow:
/// 1. Check if the health provider is available.
/// 2. Check write permissions (full bundle on Android).
/// 3. Load the GPS route points for the session.
/// 4. Call [IHealthProvider.writeWorkout] to create the workout + route.
/// 5. On Android: write HR data points via [IHealthProvider.writeHrSamples].
///
/// Conforms to [O4]: single `call()` method.
final class ExportWorkoutToHealth {
  final IHealthProvider _healthProvider;
  final IPointsRepo _pointsRepo;

  const ExportWorkoutToHealth({
    required IHealthProvider healthProvider,
    required IPointsRepo pointsRepo,
  })  : _healthProvider = healthProvider,
        _pointsRepo = pointsRepo;

  /// Export the workout identified by [sessionId] to the platform health store.
  ///
  /// [startMs] and [endMs] are Unix epoch milliseconds (UTC).
  /// [totalDistanceM] is the final accumulated distance.
  /// [totalCalories] is the estimated total energy burned (optional).
  /// [avgBpm] and [maxBpm] are summary stats used for logging.
  /// [hrSamples] is the list of per-second HR data points captured during the
  /// run. On Android, these are explicitly written to Health Connect. On iOS,
  /// Apple Watch auto-correlates HR data with the workout.
  Future<WorkoutExportResult> call({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    // 1. Check availability.
    final available = await _healthProvider.isAvailable();
    if (!available) {
      return const WorkoutExportResult(
        workoutSaved: false,
        message: 'Health service not available on this device.',
      );
    }

    // 2. Check write permissions (full bundle).
    final hasPerm = await _healthProvider.hasPermissions(_exportScopes);
    if (!hasPerm) {
      AppLogger.info(
        'Missing export permissions — skipping export',
        tag: _tag,
      );
      return const WorkoutExportResult(
        workoutSaved: false,
        message: 'Write workout permission not granted.',
      );
    }

    // 3. Load GPS route.
    List<LocationPointEntity> route;
    try {
      route = await _pointsRepo.getBySessionId(sessionId);
    } on Exception catch (e) {
      AppLogger.warn('Failed to load route for export: $e', tag: _tag);
      route = const [];
    }

    // 4. Write workout + route to health store.
    final start = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);

    final result = await _healthProvider.writeWorkout(
      start: start,
      end: end,
      totalDistanceM: totalDistanceM,
      totalCalories: totalCalories,
      route: route,
      title: 'Omni Runner',
    );

    AppLogger.info(
      'Export result: saved=${result.workoutSaved} '
      'route=${result.routeAttached} (${result.routePointCount} pts) '
      '— ${result.message}',
      tag: _tag,
    );

    // 5. Write HR samples (Android only — iOS auto-correlates via Apple Watch).
    if (result.workoutSaved && hrSamples.isNotEmpty && Platform.isAndroid) {
      try {
        final written = await _healthProvider.writeHrSamples(hrSamples);
        AppLogger.info(
          'HR export: $written / ${hrSamples.length} samples written',
          tag: _tag,
        );
      } on Exception catch (e) {
        AppLogger.warn('HR sample export failed: $e', tag: _tag);
      }
    }

    return result;
  }
}
