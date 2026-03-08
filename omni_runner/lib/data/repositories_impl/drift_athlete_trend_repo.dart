import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';

/// Drift implementation of [IAthleteTrendRepo].
final class DriftAthleteTrendRepo implements IAthleteTrendRepo {
  final AppDatabase _db;

  const DriftAthleteTrendRepo(this._db);

  @override
  Future<void> save(AthleteTrendEntity trend) async {
    final companion = _toCompanion(trend);
    await _db.into(_db.athleteTrends).insert(companion, mode: InsertMode.insertOrReplace);
  }

  @override
  Future<AthleteTrendEntity?> getById(String id) async {
    final query = _db.select(_db.athleteTrends)
      ..where((t) => t.trendUuid.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<AthleteTrendEntity?> getByUserGroupMetricPeriod({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
    required EvolutionPeriod period,
  }) async {
    final query = _db.select(_db.athleteTrends)
      ..where((t) =>
          t.userId.equals(userId) &
          t.groupId.equals(groupId) &
          t.metricOrdinal.equals(metric.name) &
          t.periodOrdinal.equals(period.name))
      ..orderBy([(t) => OrderingTerm.desc(t.analyzedAtMs)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<AthleteTrendEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  }) async {
    final query = _db.select(_db.athleteTrends)
      ..where(
          (t) => t.userId.equals(userId) & t.groupId.equals(groupId));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<AthleteTrendEntity>> getByGroup(String groupId) async {
    final query = _db.select(_db.athleteTrends)
      ..where((t) => t.groupId.equals(groupId));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<AthleteTrendEntity>> getByGroupAndDirection({
    required String groupId,
    required TrendDirection direction,
  }) async {
    final query = _db.select(_db.athleteTrends)
      ..where((t) =>
          t.groupId.equals(groupId) &
          t.directionOrdinal.equals(direction.name));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    final stmt = _db.delete(_db.athleteTrends)
      ..where((t) => t.trendUuid.equals(id));
    await stmt.go();
  }

  // ── Mappers ──

  static AthleteTrendsCompanion _toCompanion(AthleteTrendEntity e) =>
      AthleteTrendsCompanion.insert(
        trendUuid: e.id,
        userId: e.userId,
        groupId: e.groupId,
        metricOrdinal: e.metric.name,
        periodOrdinal: e.period.name,
        directionOrdinal: e.direction.name,
        currentValue: e.currentValue,
        baselineValue: e.baselineValue,
        changePercent: e.changePercent,
        dataPoints: e.dataPoints,
        latestPeriodKey: e.latestPeriodKey,
        analyzedAtMs: e.analyzedAtMs,
      );

  static AthleteTrendEntity _toEntity(AthleteTrend r) => AthleteTrendEntity(
        id: r.trendUuid,
        userId: r.userId,
        groupId: r.groupId,
        metric: safeByName(EvolutionMetric.values, r.metricOrdinal, fallback: EvolutionMetric.avgPace),
        period: safeByName(EvolutionPeriod.values, r.periodOrdinal, fallback: EvolutionPeriod.weekly),
        direction: safeByName(TrendDirection.values, r.directionOrdinal, fallback: TrendDirection.stable),
        currentValue: r.currentValue,
        baselineValue: r.baselineValue,
        changePercent: r.changePercent,
        dataPoints: r.dataPoints,
        latestPeriodKey: r.latestPeriodKey,
        analyzedAtMs: r.analyzedAtMs,
      );
}
