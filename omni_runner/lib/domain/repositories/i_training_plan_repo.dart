import 'package:omni_runner/domain/entities/plan_workout_entity.dart';

/// Contrato do repositório de planilhas e treinos do atleta.
abstract class ITrainingPlanRepo {
  /// Busca o delta de sincronização desde [since].
  /// Retorna a lista de workouts atualizados e o novo cursor.
  Future<SyncDeltaResult> getSyncDelta({
    required String deviceId,
    DateTime? since,
  });

  /// Retorna os treinos do atleta para um período.
  Future<List<PlanWorkoutEntity>> getWorkoutsForPeriod({
    required DateTime from,
    required DateTime to,
  });

  /// Retorna um treino específico por ID.
  Future<PlanWorkoutEntity?> getWorkoutById(String releaseId);

  /// Atleta inicia o treino.
  Future<void> startWorkout(String releaseId);

  /// Atleta marca o treino como concluído.
  Future<String> completeWorkout({
    required String releaseId,
    double? actualDistanceM,
    int? actualDurationS,
    double? actualAvgHr,
    int? perceivedEffort,
    int? mood,
    String source,
  });

  /// Atleta envia feedback do treino.
  Future<String> submitFeedback({
    required String releaseId,
    int? rating,
    int? perceivedEffort,
    int? mood,
    String? howWasIt,
    String? whatWasHard,
    String? notes,
  });
}

/// Resultado do sync incremental.
class SyncDeltaResult {
  const SyncDeltaResult({
    required this.workouts,
    required this.cursor,
    required this.count,
  });

  final List<PlanWorkoutEntity> workouts;

  /// Timestamp do último registro retornado — usar como `since` no próximo sync.
  final DateTime cursor;
  final int count;
}
