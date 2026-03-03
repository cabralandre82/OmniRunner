import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';

final class ImportExecution {
  final IWearableRepo _repo;

  const ImportExecution({required IWearableRepo repo}) : _repo = repo;

  Future<WorkoutExecutionEntity> call({
    String? assignmentId,
    required int durationSeconds,
    int? distanceMeters,
    int? avgPace,
    int? avgHr,
    int? maxHr,
    int? calories,
    String source = 'manual',
    String? providerActivityId,
  }) {
    return _repo.importExecution(
      assignmentId: assignmentId,
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      avgPace: avgPace,
      avgHr: avgHr,
      maxHr: maxHr,
      calories: calories,
      source: source,
      providerActivityId: providerActivityId,
    );
  }
}
