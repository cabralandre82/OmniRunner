import 'package:permission_handler/permission_handler.dart';

import 'package:omni_runner/domain/entities/background_permission_state.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';

/// Maps [PermissionStatus] (permission_handler plugin) to domain enums.
///
/// Data layer only. Isolates platform-specific enums from the domain layer,
/// maintaining Clean Architecture boundary.
///
/// No state. No side effects. Pure mapping functions.
abstract final class PermissionMapper {
  /// Convert [PermissionStatus] to [PermissionStatusEntity].
  ///
  /// Mapping:
  /// - [PermissionStatus.granted] → [PermissionStatusEntity.granted]
  /// - [PermissionStatus.limited] → [PermissionStatusEntity.granted]
  /// - [PermissionStatus.denied] → [PermissionStatusEntity.denied]
  /// - [PermissionStatus.permanentlyDenied] → [PermissionStatusEntity.permanentlyDenied]
  /// - [PermissionStatus.restricted] → [PermissionStatusEntity.restricted]
  /// - [PermissionStatus.provisional] → [PermissionStatusEntity.granted]
  static PermissionStatusEntity toForeground(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited =>
        PermissionStatusEntity.granted,
      PermissionStatus.denied => PermissionStatusEntity.denied,
      PermissionStatus.permanentlyDenied =>
        PermissionStatusEntity.permanentlyDenied,
      PermissionStatus.restricted => PermissionStatusEntity.restricted,
      PermissionStatus.provisional => PermissionStatusEntity.granted,
    };
  }

  /// Convert [PermissionStatus] to [BackgroundPermissionState].
  ///
  /// Mapping:
  /// - [PermissionStatus.granted] → [BackgroundPermissionState.granted]
  /// - [PermissionStatus.limited] → [BackgroundPermissionState.granted]
  /// - [PermissionStatus.denied] → [BackgroundPermissionState.rationaleRequired]
  /// - [PermissionStatus.permanentlyDenied] → [BackgroundPermissionState.denied]
  /// - [PermissionStatus.restricted] → [BackgroundPermissionState.denied]
  /// - [PermissionStatus.provisional] → [BackgroundPermissionState.granted]
  static BackgroundPermissionState toBackground(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited =>
        BackgroundPermissionState.granted,
      PermissionStatus.denied => BackgroundPermissionState.rationaleRequired,
      PermissionStatus.permanentlyDenied => BackgroundPermissionState.denied,
      PermissionStatus.restricted => BackgroundPermissionState.denied,
      PermissionStatus.provisional => BackgroundPermissionState.granted,
    };
  }
}
