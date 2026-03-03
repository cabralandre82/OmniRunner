import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';

final class ListTrainingSessions {
  final ITrainingSessionRepo _repo;

  const ListTrainingSessions({required ITrainingSessionRepo repo}) : _repo = repo;

  Future<List<TrainingSessionEntity>> call({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  }) {
    return _repo.listByGroup(
      groupId: groupId,
      from: from,
      to: to,
      status: status,
      limit: limit,
      offset: offset,
    );
  }
}
