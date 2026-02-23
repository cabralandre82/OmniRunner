import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/health_step_sample.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';

/// Health Connect availability status (Android only).
enum HealthConnectAvailability {
  /// Health Connect is installed and ready.
  available,

  /// Health Connect is installed but needs a provider update.
  needsUpdate,

  /// Health Connect is not installed on this device.
  unavailable,

  /// Not applicable (iOS — HealthKit has no separate install).
  notApplicable,
}

/// Permission scope for health data access.
enum HealthPermissionScope {
  /// Read heart rate data.
  readHeartRate,

  /// Read step count data.
  readSteps,

  /// Write workout / exercise session record.
  writeWorkout,

  /// Write heart rate data points.
  writeHeartRate,

  /// Write distance data (Android: DistanceRecord).
  writeDistance,

  /// Write exercise route / GPS track.
  writeExerciseRoute,

  /// Write calories burned data (Android: TotalCaloriesBurnedRecord).
  writeCalories,
}

/// Contract for accessing platform health data (HealthKit / Health Connect).
///
/// Domain-facing interface. Implementation wraps the `health` package.
/// All methods are async. Returns domain types only — no plugin types leak.
abstract interface class IHealthProvider {
  /// Whether the platform health service is available on this device.
  ///
  /// Returns `false` on iOS Simulator, iPod Touch, or Android without
  /// Health Connect installed.
  Future<bool> isAvailable();

  /// Detailed Health Connect availability status (Android only).
  ///
  /// Returns [HealthConnectAvailability.notApplicable] on iOS.
  /// Use this to show targeted UI: "Install Health Connect" vs "Update needed".
  Future<HealthConnectAvailability> getHealthConnectStatus();

  /// Open the app store to install Health Connect (Android only).
  ///
  /// No-op on iOS.
  Future<void> installHealthConnect();

  /// Check if the requested permissions have been granted.
  ///
  /// Note: On iOS, HealthKit does NOT tell you if read permissions were
  /// denied — it simply returns empty data. This method is best-effort.
  Future<bool> hasPermissions(List<HealthPermissionScope> scopes);

  /// Request health data permissions from the user.
  ///
  /// Returns `null` on success or a [HealthFailure] on failure/denial.
  /// On iOS, shows the native HealthKit authorization dialog.
  /// On Android, opens Health Connect permissions screen.
  Future<HealthFailure?> requestPermissions(
    List<HealthPermissionScope> scopes,
  );

  /// Read heart rate samples within a time range.
  ///
  /// Returns samples sorted by start time ascending.
  /// Returns empty list if no data or permission denied (iOS behavior).
  Future<List<HealthHrSample>> readHeartRate({
    required DateTime start,
    required DateTime end,
  });

  /// Read step count samples within a time range.
  ///
  /// Returns samples sorted by start time ascending.
  /// Each sample represents a window of accumulated steps.
  Future<List<HealthStepSample>> readSteps({
    required DateTime start,
    required DateTime end,
  });

  /// Get total step count for a time range (aggregated).
  ///
  /// Returns `null` if data is unavailable or permission denied.
  Future<int?> getTotalSteps({
    required DateTime start,
    required DateTime end,
  });

  /// Write a completed workout to the platform health service.
  ///
  /// Creates an HKWorkout (iOS) or Exercise record (Android) with
  /// the given metadata. If [route] is not empty, attempts to attach
  /// the GPS route to the workout.
  ///
  /// Returns a [WorkoutExportResult] describing what was saved.
  ///
  /// Requires [HealthPermissionScope.writeWorkout] permission.
  /// On Android, also requires [HealthPermissionScope.writeDistance],
  /// [HealthPermissionScope.writeExerciseRoute], and optionally
  /// [HealthPermissionScope.writeCalories].
  Future<WorkoutExportResult> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double totalDistanceM,
    int? totalCalories,
    List<LocationPointEntity> route = const [],
    String? title,
  });

  /// Write heart rate data points to the platform health service.
  ///
  /// On iOS, HealthKit automatically correlates HR data from Apple Watch
  /// with workouts, so this is typically only needed on Android.
  ///
  /// Returns the number of samples successfully written.
  ///
  /// Requires [HealthPermissionScope.writeHeartRate] permission.
  Future<int> writeHrSamples(List<HealthHrSample> samples);
}
