import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';

/// Contract for persisting and retrieving coaching group rankings.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class ICoachingRankingRepo {
  /// Save a complete ranking snapshot (header + entries).
  ///
  /// Replaces any existing snapshot with the same [CoachingGroupRankingEntity.id].
  Future<void> save(CoachingGroupRankingEntity ranking);

  /// Retrieve a ranking snapshot by its unique ID.
  Future<CoachingGroupRankingEntity?> getById(String id);

  /// Retrieve the latest ranking for a group + metric + periodKey.
  Future<CoachingGroupRankingEntity?> getByGroupMetricPeriod(
    String groupId,
    CoachingRankingMetric metric,
    String periodKey,
  );

  /// All ranking snapshots for a group, ordered by computedAtMs desc.
  Future<List<CoachingGroupRankingEntity>> getByGroupId(String groupId);

  /// Delete a ranking snapshot and its entries.
  Future<void> deleteById(String id);
}
