import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class AssignWorkout {
  final IWorkoutRepo _repo;

  const AssignWorkout({required IWorkoutRepo repo}) : _repo = repo;

  Future<WorkoutAssignmentEntity> call({
    required String templateId,
    required String athleteUserId,
    required DateTime scheduledDate,
    String? notes,
  }) {
    return _repo.assignWorkout(
      templateId: templateId,
      athleteUserId: athleteUserId,
      scheduledDate: scheduledDate,
      notes: notes,
    );
  }
}
