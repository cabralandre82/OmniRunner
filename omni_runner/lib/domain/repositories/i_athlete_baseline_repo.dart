import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

/// Contract for persisting athlete baseline snapshots.
abstract interface class IAthleteBaselineRepo {
  /// Inserts or replaces a baseline record (keyed by UUID).
  Future<void> save(AthleteBaselineEntity baseline);

  /// Retrieves a single baseline by its UUID.
  Future<AthleteBaselineEntity?> getById(String id);

  /// Retrieves the baseline for a specific (userId, groupId, metric) tuple.
  Future<AthleteBaselineEntity?> getByUserGroupMetric({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
  });

  /// Lists all baselines for a user within a coaching group.
  Future<List<AthleteBaselineEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  });

  /// Deletes a baseline by its UUID.
  Future<void> deleteById(String id);
}
