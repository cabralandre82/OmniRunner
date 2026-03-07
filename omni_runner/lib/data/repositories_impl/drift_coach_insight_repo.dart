import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';

/// Drift implementation of [ICoachInsightRepo].
final class DriftCoachInsightRepo implements ICoachInsightRepo {
  final AppDatabase _db;

  const DriftCoachInsightRepo(this._db);

  @override
  Future<void> save(CoachInsightEntity insight) async {
    final companion = _toCompanion(insight);
    await _db.into(_db.coachInsights).insertOnConflictUpdate(companion);
  }

  @override
  Future<void> update(CoachInsightEntity insight) => save(insight);

  @override
  Future<void> saveAll(List<CoachInsightEntity> insights) async {
    if (insights.isEmpty) return;
    await _db.batch((batch) {
      for (final insight in insights) {
        batch.insert(
          _db.coachInsights,
          _toCompanion(insight),
          onConflict: DoUpdate((_) => _toCompanion(insight)),
        );
      }
    });
  }

  @override
  Future<CoachInsightEntity?> getById(String id) async {
    final query = _db.select(_db.coachInsights)
      ..where((t) => t.insightUuid.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<CoachInsightEntity>> getByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final query = _db.select(_db.coachInsights)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<CoachInsightEntity>> getUnreadByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final query = _db.select(_db.coachInsights)
      ..where((t) =>
          t.groupId.equals(groupId) &
          t.readAtMs.equals(-1) &
          t.dismissed.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<CoachInsightEntity>> getByGroupAndType({
    required String groupId,
    required InsightType type,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = _db.select(_db.coachInsights)
      ..where((t) =>
          t.groupId.equals(groupId) &
          t.typeOrdinal.equals(type.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> countUnreadByGroupId(String groupId) async {
    final countExpr = _db.coachInsights.id.count();
    final query = _db.selectOnly(_db.coachInsights)
      ..addColumns([countExpr])
      ..where(
        _db.coachInsights.groupId.equals(groupId) &
        _db.coachInsights.readAtMs.equals(-1) &
        _db.coachInsights.dismissed.equals(false),
      );
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  @override
  Future<void> deleteById(String id) async {
    final stmt = _db.delete(_db.coachInsights)
      ..where((t) => t.insightUuid.equals(id));
    await stmt.go();
  }

  // ── Mappers ──

  static CoachInsightsCompanion _toCompanion(CoachInsightEntity e) =>
      CoachInsightsCompanion.insert(
        insightUuid: e.id,
        groupId: e.groupId,
        targetUserId: e.targetUserId ?? '',
        targetDisplayName: e.targetDisplayName ?? '',
        typeOrdinal: e.type.name,
        priorityOrdinal: e.priority.name,
        title: e.title,
        message: e.message,
        metricOrdinal: e.metric?.name ?? '',
        referenceValue: e.referenceValue ?? double.nan,
        changePercent: e.changePercent ?? double.nan,
        relatedEntityId: e.relatedEntityId ?? '',
        createdAtMs: e.createdAtMs,
        readAtMs: e.readAtMs ?? -1,
        dismissed: e.dismissed,
      );

  static CoachInsightEntity _toEntity(CoachInsight r) => CoachInsightEntity(
        id: r.insightUuid,
        groupId: r.groupId,
        targetUserId: r.targetUserId.isEmpty ? null : r.targetUserId,
        targetDisplayName:
            r.targetDisplayName.isEmpty ? null : r.targetDisplayName,
        type: safeByName(InsightType.values, r.typeOrdinal, fallback: InsightType.performanceDecline),
        priority: safeByName(InsightPriority.values, r.priorityOrdinal, fallback: InsightPriority.low),
        title: r.title,
        message: r.message,
        metric: r.metricOrdinal.isEmpty
            ? null
            : safeByName(EvolutionMetric.values, r.metricOrdinal, fallback: EvolutionMetric.avgPace),
        referenceValue: r.referenceValue.isNaN ? null : r.referenceValue,
        changePercent: r.changePercent.isNaN ? null : r.changePercent,
        relatedEntityId:
            r.relatedEntityId.isEmpty ? null : r.relatedEntityId,
        createdAtMs: r.createdAtMs,
        readAtMs: r.readAtMs < 0 ? null : r.readAtMs,
        dismissed: r.dismissed,
      );
}
