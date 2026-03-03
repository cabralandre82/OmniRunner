import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/entities/workout_execution_entity.dart';

abstract interface class IWearableRepo {
  Future<List<DeviceLinkEntity>> listDeviceLinks(String athleteUserId);

  Future<DeviceLinkEntity> linkDevice({
    required String groupId,
    required String provider,
    String? accessToken,
    String? refreshToken,
  });

  Future<void> unlinkDevice(String linkId);

  Future<Map<String, dynamic>> generateWorkoutPayload(String assignmentId);

  Future<WorkoutExecutionEntity> importExecution({
    String? assignmentId,
    required int durationSeconds,
    int? distanceMeters,
    int? avgPace,
    int? avgHr,
    int? maxHr,
    int? calories,
    String source = 'manual',
    String? providerActivityId,
  });

  Future<List<WorkoutExecutionEntity>> listExecutions({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  });
}
