import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/failures/ble_failure.dart';
import 'package:omni_runner/domain/repositories/i_ble_permission.dart';

/// Ensures BLE is available and permissions are granted.
///
/// Single responsibility: verify the device is ready for BLE HR scanning.
///
/// Flow:
/// 1. Check hardware support -> fail if not supported.
/// 2. Check adapter state -> fail if off.
/// 3. Check/request BLUETOOTH_SCAN permission.
/// 4. Check/request BLUETOOTH_CONNECT permission.
/// 5. Return null on success, typed [BleFailure] on failure.
///
/// Conforms to [O4]: single `call()` method.
final class EnsureBleReady {
  final IBlePermission _permission;

  const EnsureBleReady(this._permission);

  /// Returns `null` on success (BLE is ready for scanning).
  /// Returns a [BleFailure] describing why BLE is not available.
  Future<BleFailure?> call() async {
    // Step 1: Hardware support.
    final supported = await _permission.isSupported();
    if (!supported) {
      return const BleNotSupported();
    }

    // Step 2: Adapter state.
    final adapterOn = await _permission.isAdapterOn();
    if (!adapterOn) {
      return const BleAdapterOff();
    }

    // Step 3: BLUETOOTH_SCAN permission.
    var scanStatus = await _permission.checkScan();
    if (scanStatus == PermissionStatusEntity.notDetermined ||
        scanStatus == PermissionStatusEntity.denied) {
      scanStatus = await _permission.requestScan();
    }
    final scanFailure = _evaluatePermission(scanStatus, isScan: true);
    if (scanFailure != null) return scanFailure;

    // Step 4: BLUETOOTH_CONNECT permission.
    var connectStatus = await _permission.checkConnect();
    if (connectStatus == PermissionStatusEntity.notDetermined ||
        connectStatus == PermissionStatusEntity.denied) {
      connectStatus = await _permission.requestConnect();
    }
    return _evaluatePermission(connectStatus, isScan: false);
  }

  BleFailure? _evaluatePermission(
    PermissionStatusEntity status, {
    required bool isScan,
  }) {
    return switch (status) {
      PermissionStatusEntity.granted => null,
      PermissionStatusEntity.denied =>
        isScan ? const BleScanPermissionDenied() : const BleConnectPermissionDenied(),
      PermissionStatusEntity.permanentlyDenied =>
        const BlePermissionPermanentlyDenied(),
      PermissionStatusEntity.restricted =>
        const BlePermissionPermanentlyDenied(),
      PermissionStatusEntity.notDetermined =>
        isScan ? const BleScanPermissionDenied() : const BleConnectPermissionDenied(),
    };
  }
}
