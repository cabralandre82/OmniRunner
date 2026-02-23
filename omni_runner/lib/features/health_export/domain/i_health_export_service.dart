import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';

/// High-level contract for exporting workouts to platform health stores.
///
/// Bridges the existing [ExportWorkoutToHealth] use case with a
/// feature-flagged, platform-aware API that the presentation layer
/// can call without knowing HealthKit vs Health Connect details.
///
/// ## Platform behavior
///
/// **iOS (HealthKit)**
/// - Writes `HKWorkout` with attached `HKWorkoutRoute` (GPS points).
/// - HR data is auto-correlated by Apple Watch — not written explicitly.
/// - Ref: https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder
///
/// **Android (Health Connect)**
/// - Writes `ExerciseSessionRecord` + `ExerciseRoute` + `DistanceRecord`.
/// - HR data must be written explicitly as `HeartRateRecord` entries.
/// - Requires `ACTIVITY_RECOGNITION` runtime permission + Health Connect app.
/// - Ref: https://developer.android.com/health-and-fitness/guides/health-connect
///
/// ## Error handling
///
/// Methods return [WorkoutExportResult] on success or throw a
/// [HealthExportFailure] subclass on failure (from `health_export_failures.dart`).
abstract interface class IHealthExportService {
  /// Whether exporting is supported on the current platform.
  ///
  /// Returns `false` on unsupported devices (iPod Touch, Android without
  /// Health Connect, web, desktop).
  Future<bool> isSupported();

  /// Check (and optionally request) the write permissions needed for export.
  ///
  /// If [requestIfMissing] is `true` and permissions are not granted,
  /// the native permission dialog is shown.
  ///
  /// Returns `true` if all required permissions are granted.
  /// Throws [HealthExportPermissionDenied] if the user declines.
  Future<bool> ensurePermissions({bool requestIfMissing = true});

  /// Export a completed workout to the platform health store.
  ///
  /// Writes the workout record, attaches the GPS route if available,
  /// and on Android writes HR samples explicitly.
  ///
  /// [sessionId] is used to load the GPS route from [IPointsRepo].
  /// [startMs] / [endMs] are Unix epoch milliseconds (UTC).
  /// [totalDistanceM] is the final accumulated distance in meters.
  /// [totalCalories] is the estimated energy burned (optional).
  /// [hrSamples] is the list of per-second HR data captured during the run.
  ///
  /// Returns [WorkoutExportResult] describing what was written.
  /// Throws [HealthExportFailure] subclass on unrecoverable errors.
  Future<WorkoutExportResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples,
  });
}
