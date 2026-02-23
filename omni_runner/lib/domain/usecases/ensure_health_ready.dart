import 'dart:io' show Platform;

import 'package:omni_runner/domain/entities/permission_status_entity.dart';
import 'package:omni_runner/domain/failures/health_failure.dart';
import 'package:omni_runner/domain/repositories/i_health_provider.dart';

/// Callback type for requesting ACTIVITY_RECOGNITION runtime permission.
///
/// Returns a [PermissionStatusEntity] after requesting the permission.
/// On iOS this should return [PermissionStatusEntity.granted] immediately
/// (ACTIVITY_RECOGNITION is not required on iOS).
typedef ActivityRecognitionRequester = Future<PermissionStatusEntity> Function();

/// Ensures the platform health service is available and permissions are granted.
///
/// Orchestration flow:
/// 1. Check if health service is available on the device.
/// 2. On Android: request ACTIVITY_RECOGNITION runtime permission.
/// 3. Request the specified health permission scopes.
/// 4. Returns `null` on success, or a [HealthFailure] describing the issue.
///
/// Conforms to [O4]: single `call()` method.
final class EnsureHealthReady {
  final IHealthProvider _provider;
  final ActivityRecognitionRequester? _requestActivityRecognition;

  const EnsureHealthReady(
    this._provider, {
    ActivityRecognitionRequester? requestActivityRecognition,
  }) : _requestActivityRecognition = requestActivityRecognition;

  /// Check availability, request activity recognition (Android), and
  /// request health permissions for the given [scopes].
  ///
  /// Default scopes: read HR + read steps (the minimum for core tracking).
  Future<HealthFailure?> call({
    List<HealthPermissionScope> scopes = const [
      HealthPermissionScope.readHeartRate,
      HealthPermissionScope.readSteps,
    ],
  }) async {
    final available = await _provider.isAvailable();
    if (!available) {
      return const HealthNotAvailable();
    }

    // On Android, ACTIVITY_RECOGNITION must be granted before reading steps.
    if (Platform.isAndroid && _requestActivityRecognition != null) {
      final arStatus = await _requestActivityRecognition();
      if (arStatus != PermissionStatusEntity.granted) {
        return const HealthPermissionDenied();
      }
    }

    return _provider.requestPermissions(scopes);
  }
}
