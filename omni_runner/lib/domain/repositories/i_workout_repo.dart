import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';

abstract interface class IWorkoutRepo {
  // Templates
  Future<WorkoutTemplateEntity> createTemplate(WorkoutTemplateEntity template);
  Future<WorkoutTemplateEntity> updateTemplate(WorkoutTemplateEntity template);
  Future<void> deleteTemplate(String templateId);
  Future<List<WorkoutTemplateEntity>> listTemplates(String groupId);
  Future<WorkoutTemplateEntity?> getTemplateById(String templateId);

  // Blocks
  Future<void> saveBlocks(String templateId, List<WorkoutBlockEntity> blocks);

  // Assignments
  Future<WorkoutAssignmentEntity> assignWorkout({
    required String templateId,
    required String athleteUserId,
    required DateTime scheduledDate,
    String? notes,
  });
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  });
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByAthlete({
    required String groupId,
    required String athleteUserId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  });
  Future<void> updateAssignmentStatus(
      String assignmentId, WorkoutAssignmentStatus status);
}
