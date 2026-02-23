import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Low-level datasource wrapping [flutter_blue_plus] and [permission_handler]
/// for BLE permissions and adapter status.
///
/// Returns raw plugin types. Translation to domain enums happens in the
/// repository layer via [PermissionMapper].
class BlePermissionService {
  /// Whether the device hardware supports Bluetooth Low Energy.
  Future<bool> isSupported() async {
    return FlutterBluePlus.isSupported;
  }

  /// Whether the Bluetooth adapter is currently powered on.
  Future<bool> isAdapterOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Check BLUETOOTH_SCAN permission without prompting.
  Future<PermissionStatus> checkScan() async {
    return Permission.bluetoothScan.status;
  }

  /// Request BLUETOOTH_SCAN permission from the user.
  Future<PermissionStatus> requestScan() async {
    return Permission.bluetoothScan.request();
  }

  /// Check BLUETOOTH_CONNECT permission without prompting.
  Future<PermissionStatus> checkConnect() async {
    return Permission.bluetoothConnect.status;
  }

  /// Request BLUETOOTH_CONNECT permission from the user.
  Future<PermissionStatus> requestConnect() async {
    return Permission.bluetoothConnect.request();
  }

  /// Open the app's system settings page.
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}
