import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';

/// Drift implementation of [IAthleteBaselineRepo].
final class DriftAthleteBaselineRepo implements IAthleteBaselineRepo {
  final AppDatabase _db;

  const DriftAthleteBaselineRepo(this._db);

  @override
  Future<void> save(AthleteBaselineEntity baseline) async {
    final companion = _toCompanion(baseline);
    await _db.into(_db.athleteBaselines).insert(companion, mode: InsertMode.insertOrReplace);
  }

  @override
  Future<AthleteBaselineEntity?> getById(String id) async {
    final query = _db.select(_db.athleteBaselines)
      ..where((t) => t.baselineUuid.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<AthleteBaselineEntity?> getByUserGroupMetric({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
  }) async {
    final query = _db.select(_db.athleteBaselines)
      ..where((t) =>
          t.userId.equals(userId) &
          t.groupId.equals(groupId) &
          t.metricOrdinal.equals(metric.name))
      ..orderBy([(t) => OrderingTerm.desc(t.computedAtMs)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<AthleteBaselineEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  }) async {
    final query = _db.select(_db.athleteBaselines)
      ..where(
          (t) => t.userId.equals(userId) & t.groupId.equals(groupId));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    final stmt = _db.delete(_db.athleteBaselines)
      ..where((t) => t.baselineUuid.equals(id));
    await stmt.go();
  }

  // ── Mappers ──

  static AthleteBaselinesCompanion _toCompanion(AthleteBaselineEntity e) =>
      AthleteBaselinesCompanion.insert(
        baselineUuid: e.id,
        userId: e.userId,
        groupId: e.groupId,
        metricOrdinal: e.metric.name,
        value: e.value,
        sampleSize: e.sampleSize,
        windowStartMs: e.windowStartMs,
        windowEndMs: e.windowEndMs,
        computedAtMs: e.computedAtMs,
      );

  static AthleteBaselineEntity _toEntity(AthleteBaseline r) =>
      AthleteBaselineEntity(
        id: r.baselineUuid,
        userId: r.userId,
        groupId: r.groupId,
        metric: safeByName(EvolutionMetric.values, r.metricOrdinal, fallback: EvolutionMetric.avgPace),
        value: r.value,
        sampleSize: r.sampleSize,
        windowStartMs: r.windowStartMs,
        windowEndMs: r.windowEndMs,
        computedAtMs: r.computedAtMs,
      );
}
