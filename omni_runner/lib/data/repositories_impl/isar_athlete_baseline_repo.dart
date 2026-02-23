import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/athlete_baseline_model.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';

/// Isar implementation of [IAthleteBaselineRepo].
final class IsarAthleteBaselineRepo implements IAthleteBaselineRepo {
  final Isar _isar;

  const IsarAthleteBaselineRepo(this._isar);

  @override
  Future<void> save(AthleteBaselineEntity baseline) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.athleteBaselineRecords
          .where()
          .baselineUuidEqualTo(baseline.id)
          .findFirst();

      final record = _toRecord(baseline);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.athleteBaselineRecords.put(record);
    });
  }

  @override
  Future<AthleteBaselineEntity?> getById(String id) async {
    final record = await _isar.athleteBaselineRecords
        .where()
        .baselineUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<AthleteBaselineEntity?> getByUserGroupMetric({
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
  }) async {
    final records = await _isar.athleteBaselineRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .groupIdEqualTo(groupId)
        .metricOrdinalEqualTo(metric.index)
        .sortByComputedAtMsDesc()
        .limit(1)
        .findAll();
    return records.isEmpty ? null : _toEntity(records.first);
  }

  @override
  Future<List<AthleteBaselineEntity>> getByUserAndGroup({
    required String userId,
    required String groupId,
  }) async {
    final records = await _isar.athleteBaselineRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .groupIdEqualTo(groupId)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.athleteBaselineRecords
          .where()
          .baselineUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static AthleteBaselineRecord _toRecord(AthleteBaselineEntity e) =>
      AthleteBaselineRecord()
        ..baselineUuid = e.id
        ..userId = e.userId
        ..groupId = e.groupId
        ..metricOrdinal = e.metric.index
        ..value = e.value
        ..sampleSize = e.sampleSize
        ..windowStartMs = e.windowStartMs
        ..windowEndMs = e.windowEndMs
        ..computedAtMs = e.computedAtMs;

  static AthleteBaselineEntity _toEntity(AthleteBaselineRecord r) =>
      AthleteBaselineEntity(
        id: r.baselineUuid,
        userId: r.userId,
        groupId: r.groupId,
        metric: EvolutionMetric.values[r.metricOrdinal],
        value: r.value,
        sampleSize: r.sampleSize,
        windowStartMs: r.windowStartMs,
        windowEndMs: r.windowEndMs,
        computedAtMs: r.computedAtMs,
      );
}
