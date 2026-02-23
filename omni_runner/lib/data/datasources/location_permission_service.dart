import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

/// Low-level datasource that wraps [permission_handler] and [geolocator]
/// for location permissions and service status.
///
/// Returns raw [PermissionStatus] from the plugin.
/// Translation to domain enums happens in the repository layer.
///
/// This class exists so the repository can be tested with a mock datasource.
class LocationPermissionService {
  /// Check if device location services (GPS) are enabled at system level.
  ///
  /// Uses [geolocator] which queries the OS directly.
  Future<bool> isServiceEnabled() async {
    return geo.Geolocator.isLocationServiceEnabled();
  }

  /// Check current location permission without prompting the user.
  Future<PermissionStatus> checkPermission() async {
    return Permission.locationWhenInUse.status;
  }

  /// Request location permission from the user.
  ///
  /// Shows the system permission dialog.
  Future<PermissionStatus> requestPermission() async {
    return Permission.locationWhenInUse.request();
  }

  /// Check current background location permission status.
  Future<PermissionStatus> checkBackgroundPermission() async {
    return Permission.locationAlways.status;
  }

  /// Request background location permission from the user.
  ///
  /// On Android 11+, this triggers the system settings page.
  Future<PermissionStatus> requestBackgroundPermission() async {
    return Permission.locationAlways.request();
  }

  /// Open the app's system settings page.
  ///
  /// Returns `true` if settings screen was opened successfully.
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}
