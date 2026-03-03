import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class CreateTemplate {
  final IWorkoutRepo _repo;

  const CreateTemplate({required IWorkoutRepo repo}) : _repo = repo;

  Future<WorkoutTemplateEntity> call({
    required String id,
    required String groupId,
    required String createdBy,
    required String name,
    String? description,
  }) async {
    if (name.trim().length < 2) {
      throw ArgumentError('Name must be at least 2 characters');
    }

    final now = DateTime.now();
    final template = WorkoutTemplateEntity(
      id: id,
      groupId: groupId,
      name: name.trim(),
      description: description?.trim(),
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );

    return _repo.createTemplate(template);
  }
}
