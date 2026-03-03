import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class ListTemplates {
  final IWorkoutRepo _repo;

  const ListTemplates({required IWorkoutRepo repo}) : _repo = repo;

  Future<List<WorkoutTemplateEntity>> call({required String groupId}) {
    return _repo.listTemplates(groupId);
  }
}
