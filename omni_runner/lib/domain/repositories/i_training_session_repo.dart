import 'package:omni_runner/domain/entities/training_session_entity.dart';

abstract interface class ITrainingSessionRepo {
  Future<TrainingSessionEntity> create(TrainingSessionEntity session);

  Future<TrainingSessionEntity> update(TrainingSessionEntity session);

  Future<TrainingSessionEntity?> getById(String id);

  /// List sessions for a group, ordered by starts_at desc.
  /// [from] and [to] filter by starts_at window.
  /// [status] optionally filters by session status.
  Future<List<TrainingSessionEntity>> listByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  });

  Future<void> cancel(String sessionId);
}
