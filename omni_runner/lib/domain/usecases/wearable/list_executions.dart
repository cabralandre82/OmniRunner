import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';

final class ListExecutions {
  final IWearableRepo _repo;

  const ListExecutions({required IWearableRepo repo}) : _repo = repo;

  Future<List<WorkoutExecutionEntity>> call({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  }) {
    return _repo.listExecutions(
      groupId: groupId,
      athleteUserId: athleteUserId,
      limit: limit,
    );
  }
}
