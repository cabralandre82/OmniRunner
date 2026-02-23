import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/athlete_trend_model.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';

/// Isar implementation of [IAthleteTrendRepo].
final class IsarAthleteTrendRepo implements IAthleteTrendRepo {
  final Isar _isar;

  const IsarAthleteTrendRepo(this._isar);

  @override
  Future<void> save(AthleteTrendEntity trend) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.athleteTrendRecords
          .where()
          .trendUuidEqualTo(trend.id)
          .findFirst();

      final record = _toRecord(trend);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.athleteTrendRecords.put(record);
    });
  }

  @override
  Future<AthleteTrendEntity?> getById(String id) async {
    final record = await _isar.athleteTrendRecords
        .where()
        .trendUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<AthleteTrendEntity?> getByUserGroupMetricPeriod({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
    required EvolutionPeriod period,
  }) async {
    final records = await _isar.athleteTrendRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .groupIdEqualTo(groupId)
        .metricOrdinalEqualTo(metric.index)
        .periodOrdinalEqualTo(period.index)
        .sortByAnalyzedAtMsDesc()
        .limit(1)
        .findAll();
    return records.isEmpty ? null : _toEntity(records.first);
  }

  @override
  Future<List<AthleteTrendEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  }) async {
    final records = await _isar.athleteTrendRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .groupIdEqualTo(groupId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<AthleteTrendEntity>> getByGroup(String groupId) async {
    final records = await _isar.athleteTrendRecords
        .where()
        .groupIdEqualTo(groupId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<AthleteTrendEntity>> getByGroupAndDirection({
    required String groupId,
    required TrendDirection direction,
  }) async {
    final records = await _isar.athleteTrendRecords
        .where()
        .directionOrdinalEqualTo(direction.index)
        .filter()
        .groupIdEqualTo(groupId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.athleteTrendRecords
          .where()
          .trendUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static AthleteTrendRecord _toRecord(AthleteTrendEntity e) =>
      AthleteTrendRecord()
        ..trendUuid = e.id
        ..userId = e.userId
        ..groupId = e.groupId
        ..metricOrdinal = e.metric.index
        ..periodOrdinal = e.period.index
        ..directionOrdinal = e.direction.index
        ..currentValue = e.currentValue
        ..baselineValue = e.baselineValue
        ..changePercent = e.changePercent
        ..dataPoints = e.dataPoints
        ..latestPeriodKey = e.latestPeriodKey
        ..analyzedAtMs = e.analyzedAtMs;

  static AthleteTrendEntity _toEntity(AthleteTrendRecord r) =>
      AthleteTrendEntity(
        id: r.trendUuid,
        userId: r.userId,
        groupId: r.groupId,
        metric: EvolutionMetric.values[r.metricOrdinal],
        period: EvolutionPeriod.values[r.periodOrdinal],
        direction: TrendDirection.values[r.directionOrdinal],
        currentValue: r.currentValue,
        baselineValue: r.baselineValue,
        changePercent: r.changePercent,
        dataPoints: r.dataPoints,
        latestPeriodKey: r.latestPeriodKey,
        analyzedAtMs: r.analyzedAtMs,
      );
}
