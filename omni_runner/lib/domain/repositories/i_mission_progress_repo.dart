import 'package:omni_runner/domain/entities/mission_progress_entity.dart';

/// Contract for persisting user mission progress.
abstract interface class IMissionProgressRepo {
  Future<void> save(MissionProgressEntity progress);

  /// All mission progress records for a user.
  Future<List<MissionProgressEntity>> getByUserId(String userId);

  /// Active (non-completed, non-expired) missions for a user.
  Future<List<MissionProgressEntity>> getActiveByUserId(String userId);

  /// Get progress for a specific mission assignment.
  Future<MissionProgressEntity?> getById(String id);

  /// Get progress for a user + mission combo (for dedup).
  Future<MissionProgressEntity?> getByUserAndMission(
      String userId, String missionId);
}
