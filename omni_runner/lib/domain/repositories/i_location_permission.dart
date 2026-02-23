import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';

/// Contract for checking and requesting location permissions and services.
///
/// Domain interface. Implementation lives in infrastructure.
///
/// Dependency direction: infrastructure -> domain (implements this).
abstract interface class ILocationPermission {
  /// Check if device location services (GPS) are enabled at system level.
  ///
  /// Returns `true` if location services are on, `false` otherwise.
  /// Never throws.
  Future<bool> isServiceEnabled();

  /// Check current foreground permission status without prompting the user.
  ///
  /// Never throws. Always returns a valid [PermissionStatusEntity].
  Future<PermissionStatusEntity> check();

  /// Request foreground location permission from the user.
  ///
  /// Shows the system permission dialog.
  /// Returns the resulting [PermissionStatusEntity] after user action.
  /// Never throws.
  Future<PermissionStatusEntity> request();

  /// Check current background location permission state.
  ///
  /// On Android 10 (API 29): background is bundled with foreground.
  /// On Android 11+ (API 30+): separate permission required.
  /// On iOS: handled via NSLocationAlwaysAndWhenInUseUsageDescription.
  /// Never throws.
  Future<BackgroundPermissionState> checkBackground();

  /// Request background location permission.
  ///
  /// MUST only be called after:
  /// 1. Foreground permission is [PermissionStatusEntity.granted]
  /// 2. Rationale has been shown to user
  ///
  /// On Android 11+, this opens the system settings page
  /// for "Allow all the time".
  /// Never throws.
  Future<BackgroundPermissionState> requestBackground();

  /// Open the app's system settings page.
  ///
  /// Used when permission is [PermissionStatusEntity.permanentlyDenied]
  /// or when background permission requires manual toggle.
  /// Returns `true` if settings were opened, `false` otherwise.
  Future<bool> openAppSettings();
}
