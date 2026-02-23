import 'dart:io' show Platform;

import 'package:omni_runner/core/errors/health_export_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';

const String _tag = 'HealthExport';

/// Required write scopes shared by both platforms.
const _baseScopes = [
  HealthPermissionScope.writeWorkout,
  HealthPermissionScope.writeDistance,
  HealthPermissionScope.writeExerciseRoute,
];

/// Android needs explicit HR write permission; iOS auto-correlates from Watch.
const _androidExtraScopes = [
  HealthPermissionScope.writeHeartRate,
];

/// Concrete [IHealthExportService] that delegates to [IHealthProvider].
///
/// Platform differences are handled via feature flags (`Platform.isIOS` /
/// `Platform.isAndroid`) so the presentation layer remains platform-agnostic.
///
/// ## iOS (HealthKit)
/// - Calls `writeWorkout` which creates HKWorkout + HKWorkoutRoute.
/// - HR samples are NOT written explicitly — Apple Watch auto-correlates them.
/// - Ref: https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder
///
/// ## Android (Health Connect)
/// - Checks Health Connect SDK status before proceeding.
/// - Calls `writeWorkout` for ExerciseSessionRecord + route.
/// - Writes HR samples explicitly as HeartRateRecord entries.
/// - Ref: https://developer.android.com/health-and-fitness/guides/health-connect
class HealthExportServiceImpl implements IHealthExportService {
  final IHealthProvider _healthProvider;
  final IPointsRepo _pointsRepo;

  const HealthExportServiceImpl({
    required IHealthProvider healthProvider,
    required IPointsRepo pointsRepo,
  })  : _healthProvider = healthProvider,
        _pointsRepo = pointsRepo;

  // ---------------------------------------------------------------------------
  // isSupported
  // ---------------------------------------------------------------------------

  @override
  Future<bool> isSupported() async {
    if (!_isMobilePlatform) return false;

    if (Platform.isAndroid) {
      final status = await _healthProvider.getHealthConnectStatus();
      return status == HealthConnectAvailability.available;
    }

    // iOS: HealthKit is available on all real iPhones/Apple Watches.
    return _healthProvider.isAvailable();
  }

  // ---------------------------------------------------------------------------
  // ensurePermissions
  // ---------------------------------------------------------------------------

  @override
  Future<bool> ensurePermissions({bool requestIfMissing = true}) async {
    await _checkPlatformAvailability();

    final scopes = _requiredScopes;

    final hasPerms = await _healthProvider.hasPermissions(scopes);
    if (hasPerms) return true;

    if (!requestIfMissing) {
      throw HealthExportPermissionDenied(
        missingScopes: scopes.map((s) => s.name).toList(),
      );
    }

    AppLogger.info(
      'Requesting health export permissions: '
      '${scopes.map((s) => s.name).join(', ')}',
      tag: _tag,
    );

    final failure = await _healthProvider.requestPermissions(scopes);
    if (failure != null) {
      throw HealthExportPermissionDenied(
        missingScopes: scopes.map((s) => s.name).toList(),
      );
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // exportWorkout
  // ---------------------------------------------------------------------------

  @override
  Future<WorkoutExportResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    await _checkPlatformAvailability();

    // 1. Ensure write permissions are granted.
    await ensurePermissions();

    // 2. Load GPS route.
    final route = await _loadRoute(sessionId);

    // 3. Write workout + route to health store.
    final start = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);

    AppLogger.info(
      'Exporting workout $sessionId to $_platformName: '
      '${route.length} GPS pts, ${hrSamples.length} HR samples, '
      '${totalDistanceM.round()}m',
      tag: _tag,
    );

    final result = await _healthProvider.writeWorkout(
      start: start,
      end: end,
      totalDistanceM: totalDistanceM,
      totalCalories: totalCalories,
      route: route,
      title: 'Omni Runner',
    );

    if (!result.workoutSaved) {
      throw HealthExportWriteFailed(result.message);
    }

    AppLogger.info(
      'Workout saved: route_attached=${result.routeAttached} '
      'route_pts=${result.routePointCount}',
      tag: _tag,
    );

    // 4. Write HR samples (Android only).
    if (Platform.isAndroid && hrSamples.isNotEmpty) {
      await _writeHrSamples(hrSamples);
    }

    // 5. Warn if route attachment failed (partial success).
    if (route.isNotEmpty && !result.routeAttached) {
      AppLogger.warn(
        'Route attachment failed: ${result.message}',
        tag: _tag,
      );
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Scopes required for the current platform.
  List<HealthPermissionScope> get _requiredScopes => [
        ..._baseScopes,
        if (Platform.isAndroid) ..._androidExtraScopes,
      ];

  /// Human-readable platform name for logs.
  String get _platformName =>
      Platform.isIOS ? 'HealthKit' : 'Health Connect';

  /// Guard: ensure the platform supports health export.
  ///
  /// On Android, differentiates between "not installed" and "needs update"
  /// to provide actionable guidance to the user.
  Future<void> _checkPlatformAvailability() async {
    if (!_isMobilePlatform) {
      throw const HealthExportNotAvailable(
        'Health export is only available on iOS and Android.',
      );
    }

    if (Platform.isAndroid) {
      final status = await _healthProvider.getHealthConnectStatus();
      switch (status) {
        case HealthConnectAvailability.available:
          return;
        case HealthConnectAvailability.needsUpdate:
          throw const HealthExportNeedsUpdate();
        case HealthConnectAvailability.unavailable:
          throw const HealthExportNotAvailable(
            'Health Connect is not installed. '
            'Install it from Google Play to export workouts.',
          );
        case HealthConnectAvailability.notApplicable:
          return; // Should not happen on Android.
      }
    }

    // iOS: verify HealthKit is available.
    final available = await _healthProvider.isAvailable();
    if (!available) {
      throw const HealthExportNotAvailable(
        'HealthKit is not available on this device.',
      );
    }
  }

  /// Load GPS route points for the session. Returns empty list on failure.
  Future<List<LocationPointEntity>> _loadRoute(String sessionId) async {
    try {
      return await _pointsRepo.getBySessionId(sessionId);
    } on Exception catch (e) {
      AppLogger.warn('Failed to load route for export: $e', tag: _tag);
      return const [];
    }
  }

  /// Write HR samples to Health Connect (Android only).
  ///
  /// Logs a warning on partial failure but does NOT throw — the workout
  /// record was already saved successfully, so HR failure is non-fatal.
  Future<void> _writeHrSamples(List<HealthHrSample> samples) async {
    try {
      final written = await _healthProvider.writeHrSamples(samples);
      AppLogger.info(
        'HR export: $written / ${samples.length} samples written',
        tag: _tag,
      );
      if (written < samples.length) {
        AppLogger.warn(
          'Partial HR write: only $written / ${samples.length} succeeded',
          tag: _tag,
        );
      }
    } on Exception catch (e) {
      AppLogger.warn('HR sample export failed (non-fatal): $e', tag: _tag);
    }
  }

  /// True if running on iOS or Android.
  static bool get _isMobilePlatform =>
      Platform.isIOS || Platform.isAndroid;
}
