import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class ListAssignments {
  final IWorkoutRepo _repo;

  const ListAssignments({required IWorkoutRepo repo}) : _repo = repo;

  Future<List<WorkoutAssignmentEntity>> byGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) {
    return _repo.listAssignmentsByGroup(
      groupId: groupId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<WorkoutAssignmentEntity>> byAthlete({
    required String groupId,
    required String athleteUserId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) {
    return _repo.listAssignmentsByAthlete(
      groupId: groupId,
      athleteUserId: athleteUserId,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
    );
  }
}
