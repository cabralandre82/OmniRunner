import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

/// Contract for persisting coach insights.
abstract interface class ICoachInsightRepo {
  /// Inserts or replaces an insight record (keyed by UUID).
  Future<void> save(CoachInsightEntity insight);

  /// Updates an existing insight (e.g. markRead, markDismissed).
  Future<void> update(CoachInsightEntity insight);

  /// Retrieves a single insight by its UUID.
  Future<CoachInsightEntity?> getById(String id);

  /// Lists all insights for a coaching group, newest first.
  Future<List<CoachInsightEntity>> getByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  });

  /// Lists only unread insights for a coaching group, newest first.
  Future<List<CoachInsightEntity>> getUnreadByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  });

  /// Lists insights filtered by type within a group, newest first.
  Future<List<CoachInsightEntity>> getByGroupAndType({
    required String groupId,
    required InsightType type,
    int limit = 100,
    int offset = 0,
  });

  /// Counts unread, non-dismissed insights for badge display.
  Future<int> countUnreadByGroupId(String groupId);

  /// Deletes an insight by its UUID.
  Future<void> deleteById(String id);

  /// Bulk-saves a list of insights (e.g. after a generate pass).
  Future<void> saveAll(List<CoachInsightEntity> insights);
}
