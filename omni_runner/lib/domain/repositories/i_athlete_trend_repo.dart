import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

/// Contract for persisting athlete trend analysis results.
abstract interface class IAthleteTrendRepo {
  /// Inserts or replaces a trend record (keyed by UUID).
  Future<void> save(AthleteTrendEntity trend);

  /// Retrieves a single trend by its UUID.
  Future<AthleteTrendEntity?> getById(String id);

  /// Retrieves the trend for a specific (userId, groupId, metric, period) tuple.
  Future<AthleteTrendEntity?> getByUserGroupMetricPeriod({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
    required EvolutionPeriod period,
  });

  /// Lists all trends for a user within a coaching group.
  Future<List<AthleteTrendEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  });

  /// Lists all trends for a coaching group (all athletes).
  Future<List<AthleteTrendEntity>> getByGroup(String groupId);

  /// Lists trends filtered by direction (e.g. all declining trends in a group).
  Future<List<AthleteTrendEntity>> getByGroupAndDirection({
    required String groupId,
    required TrendDirection direction,
  });

  /// Deletes a trend by its UUID.
  Future<void> deleteById(String id);
}
