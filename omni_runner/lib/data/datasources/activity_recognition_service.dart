import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

import 'package:omni_runner/data/mappers/permission_mapper.dart';
import 'package:omni_runner/domain/entities/permission_status_entity.dart';

/// Request the ACTIVITY_RECOGNITION runtime permission (Android only).
///
/// On iOS, activity recognition is not a separate permission — returns
/// [PermissionStatusEntity.granted] immediately.
///
/// This is a standalone function (not a class) because it maps directly
/// to the [ActivityRecognitionRequester] typedef in [EnsureHealthReady].
Future<PermissionStatusEntity> requestActivityRecognitionPermission() async {
  if (!Platform.isAndroid) {
    return PermissionStatusEntity.granted;
  }

  final status = await Permission.activityRecognition.status;
  if (status.isGranted) {
    return PermissionStatusEntity.granted;
  }

  final result = await Permission.activityRecognition.request();
  return PermissionMapper.toForeground(result);
}
