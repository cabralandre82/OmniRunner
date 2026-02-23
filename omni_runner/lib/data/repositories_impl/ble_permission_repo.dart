import 'package:omni_runner/data/datasources/ble_permission_service.dart';
import 'package:omni_runner/data/mappers/permission_mapper.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_ble_permission.dart';

/// Concrete implementation of [IBlePermission].
///
/// Delegates to [BlePermissionService] and maps raw plugin statuses
/// to domain enums via [PermissionMapper].
class BlePermissionRepo implements IBlePermission {
  final BlePermissionService _service;

  const BlePermissionRepo({required BlePermissionService service})
      : _service = service;

  @override
  Future<bool> isSupported() => _service.isSupported();

  @override
  Future<bool> isAdapterOn() => _service.isAdapterOn();

  @override
  Future<PermissionStatusEntity> checkScan() async {
    final status = await _service.checkScan();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<PermissionStatusEntity> requestScan() async {
    final status = await _service.requestScan();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<PermissionStatusEntity> checkConnect() async {
    final status = await _service.checkConnect();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<PermissionStatusEntity> requestConnect() async {
    final status = await _service.requestConnect();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<bool> openAppSettings() => _service.openSettings();
}
