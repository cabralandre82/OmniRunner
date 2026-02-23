import 'package:omni_runner/domain/entities/permission_status_entity.dart';

/// Contract for checking and requesting BLE permissions and adapter state.
///
/// Domain interface — implementation lives in the data layer.
/// Only covers permissions and adapter readiness.
/// Actual BLE scanning/connecting is NOT in scope here.
abstract interface class IBlePermission {
  /// Whether the device hardware supports Bluetooth Low Energy.
  Future<bool> isSupported();

  /// Whether the Bluetooth adapter is currently powered on.
  Future<bool> isAdapterOn();

  /// Check current BLUETOOTH_SCAN permission without prompting.
  Future<PermissionStatusEntity> checkScan();

  /// Request BLUETOOTH_SCAN permission from the user.
  Future<PermissionStatusEntity> requestScan();

  /// Check current BLUETOOTH_CONNECT permission without prompting.
  Future<PermissionStatusEntity> checkConnect();

  /// Request BLUETOOTH_CONNECT permission from the user.
  Future<PermissionStatusEntity> requestConnect();

  /// Open the app's system settings page.
  ///
  /// Used when permissions are permanently denied.
  Future<bool> openAppSettings();
}
