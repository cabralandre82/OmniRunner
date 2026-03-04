import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/failures/location_failure.dart';
import 'package:omni_runner/domain/repositories/i_location_permission.dart';

/// Callback type for showing a rationale dialog before requesting
/// background location. Returns `true` if the user agreed to proceed.
typedef ShowRationaleCallback = Future<bool> Function();

/// Ensures location services are enabled and permissions are granted.
///
/// Single responsibility: verify the device is ready to provide GPS data.
///
/// Flow:
/// 1. Check if location services are enabled -> if not, fail.
/// 2. Check current permission status.
/// 3. If not determined or denied, request permission.
/// 4. Evaluate final status -> return success or typed failure.
///
/// Conforms to [O4]: single `call()` method.
final class EnsureLocationReady {
  final ILocationPermission _permission;

  const EnsureLocationReady(this._permission);

  /// Returns `null` on success (location is ready).
  /// Returns a [LocationFailure] describing why location is not available.
  Future<LocationFailure?> call() async {
    // Step 1: Check if location services are enabled at system level.
    final serviceEnabled = await _permission.isServiceEnabled();
    if (!serviceEnabled) {
      return const LocationServiceDisabled();
    }

    // Step 2: Check current permission status.
    var status = await _permission.check();

    // Step 3: If not yet determined or previously denied, request permission.
    if (status == PermissionStatusEntity.notDetermined ||
        status == PermissionStatusEntity.denied) {
      status = await _permission.request();
    }

    // Step 4: Evaluate final permission status.
    return switch (status) {
      PermissionStatusEntity.granted => null,
      PermissionStatusEntity.denied => const LocationPermissionDenied(),
      PermissionStatusEntity.permanentlyDenied =>
        const LocationPermissionPermanentlyDenied(),
      PermissionStatusEntity.restricted =>
        const LocationPermissionPermanentlyDenied(),
      PermissionStatusEntity.notDetermined =>
        const LocationPermissionDenied(),
    };
  }

  /// Ensures background location permission is granted.
  ///
  /// Shows a rationale dialog via [showRationale] before requesting
  /// the system permission, as required by Android 11+ (API 30+).
  /// Returns `null` on success; a [LocationFailure] otherwise.
  Future<LocationFailure?> ensureBackground({
    required ShowRationaleCallback showRationale,
  }) async {
    final foregroundFailure = await call();
    if (foregroundFailure != null) return foregroundFailure;

    final bgState = await _permission.checkBackground();
    if (bgState == BackgroundPermissionState.granted) return null;

    if (bgState == BackgroundPermissionState.denied) {
      return const LocationPermissionPermanentlyDenied();
    }

    final userAgreed = await showRationale();
    if (!userAgreed) return const LocationPermissionDenied();

    final result = await _permission.requestBackground();
    return switch (result) {
      BackgroundPermissionState.granted => null,
      BackgroundPermissionState.denied =>
        const LocationPermissionPermanentlyDenied(),
      _ => const LocationPermissionDenied(),
    };
  }
}
