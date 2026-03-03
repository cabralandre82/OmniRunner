import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class SaveBlocks {
  final IWorkoutRepo _repo;

  const SaveBlocks({required IWorkoutRepo repo}) : _repo = repo;

  Future<void> call({
    required String templateId,
    required List<WorkoutBlockEntity> blocks,
  }) {
    return _repo.saveBlocks(templateId, blocks);
  }
}
