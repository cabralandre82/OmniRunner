import 'package:permission_handler/permission_handler.dart';

import 'package:omni_runner/data/datasources/location_permission_service.dart';
import 'package:omni_runner/data/mappers/permission_mapper.dart';
import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_location_permission.dart';

/// Concrete implementation of [ILocationPermission].
///
/// Delegates to [LocationPermissionService] and uses [PermissionMapper]
/// to translate [PermissionStatus] (plugin) → domain enums.
///
/// Dependency direction: data → domain (implements interface).
class LocationPermissionRepo implements ILocationPermission {
  final LocationPermissionService _service;

  const LocationPermissionRepo({
    required LocationPermissionService service,
  }) : _service = service;

  @override
  Future<bool> isServiceEnabled() async {
    return _service.isServiceEnabled();
  }

  @override
  Future<PermissionStatusEntity> check() async {
    final status = await _service.checkPermission();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<PermissionStatusEntity> request() async {
    final status = await _service.requestPermission();
    return PermissionMapper.toForeground(status);
  }

  @override
  Future<BackgroundPermissionState> checkBackground() async {
    // First check if foreground is granted.
    final foreground = await _service.checkPermission();
    if (foreground != PermissionStatus.granted &&
        foreground != PermissionStatus.limited) {
      return BackgroundPermissionState.notNeeded;
    }

    final status = await _service.checkBackgroundPermission();
    return PermissionMapper.toBackground(status);
  }

  @override
  Future<BackgroundPermissionState> requestBackground() async {
    final status = await _service.requestBackgroundPermission();
    return PermissionMapper.toBackground(status);
  }

  @override
  Future<bool> openAppSettings() async {
    return _service.openSettings();
  }
}
