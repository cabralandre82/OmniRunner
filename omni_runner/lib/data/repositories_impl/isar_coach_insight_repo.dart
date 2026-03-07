// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/coach_insight_model.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';

/// Isar implementation of [ICoachInsightRepo].
final class IsarCoachInsightRepo implements ICoachInsightRepo {
  final Isar _isar;

  const IsarCoachInsightRepo(this._isar);

  @override
  Future<void> save(CoachInsightEntity insight) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachInsightRecords
          .where()
          .insightUuidEqualTo(insight.id)
          .findFirst();

      final record = _toRecord(insight);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.coachInsightRecords.put(record);
    });
  }

  @override
  Future<void> update(CoachInsightEntity insight) => save(insight);

  @override
  Future<void> saveAll(List<CoachInsightEntity> insights) async {
    if (insights.isEmpty) return;
    await _isar.writeTxn(() async {
      for (final insight in insights) {
        final existing = await _isar.coachInsightRecords
            .where()
            .insightUuidEqualTo(insight.id)
            .findFirst();

        final record = _toRecord(insight);
        if (existing != null) record.isarId = existing.isarId;
        await _isar.coachInsightRecords.put(record);
      }
    });
  }

  @override
  Future<CoachInsightEntity?> getById(String id) async {
    final record = await _isar.coachInsightRecords
        .where()
        .insightUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<CoachInsightEntity>> getByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final records = await _isar.coachInsightRecords
        .where()
        .groupIdEqualTo(groupId)
        .sortByCreatedAtMsDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<CoachInsightEntity>> getUnreadByGroupId(
    String groupId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final records = await _isar.coachInsightRecords
        .where()
        .groupIdEqualTo(groupId)
        .filter()
        .readAtMsEqualTo(-1)
        .dismissedEqualTo(false)
        .sortByCreatedAtMsDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<CoachInsightEntity>> getByGroupAndType({
    required String groupId,
    required InsightType type,
    int limit = 100,
    int offset = 0,
  }) async {
    final records = await _isar.coachInsightRecords
        .where()
        .groupIdEqualTo(groupId)
        .filter()
        .typeOrdinalEqualTo(type.index)
        .sortByCreatedAtMsDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<int> countUnreadByGroupId(String groupId) async {
    return _isar.coachInsightRecords
        .where()
        .groupIdEqualTo(groupId)
        .filter()
        .readAtMsEqualTo(-1)
        .dismissedEqualTo(false)
        .count();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.coachInsightRecords
          .where()
          .insightUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static CoachInsightRecord _toRecord(CoachInsightEntity e) =>
      CoachInsightRecord()
        ..insightUuid = e.id
        ..groupId = e.groupId
        ..targetUserId = e.targetUserId ?? ''
        ..targetDisplayName = e.targetDisplayName ?? ''
        ..typeOrdinal = e.type.index
        ..priorityOrdinal = e.priority.index
        ..title = e.title
        ..message = e.message
        ..metricOrdinal = e.metric?.index ?? -1
        ..referenceValue = e.referenceValue ?? double.nan
        ..changePercent = e.changePercent ?? double.nan
        ..relatedEntityId = e.relatedEntityId ?? ''
        ..createdAtMs = e.createdAtMs
        ..readAtMs = e.readAtMs ?? -1
        ..dismissed = e.dismissed;

  static CoachInsightEntity _toEntity(CoachInsightRecord r) =>
      CoachInsightEntity(
        id: r.insightUuid,
        groupId: r.groupId,
        targetUserId: r.targetUserId.isEmpty ? null : r.targetUserId,
        targetDisplayName:
            r.targetDisplayName.isEmpty ? null : r.targetDisplayName,
        type: InsightType.values[r.typeOrdinal],
        priority: InsightPriority.values[r.priorityOrdinal],
        title: r.title,
        message: r.message,
        metric: r.metricOrdinal < 0
            ? null
            : EvolutionMetric.values[r.metricOrdinal],
        referenceValue: r.referenceValue.isNaN ? null : r.referenceValue,
        changePercent: r.changePercent.isNaN ? null : r.changePercent,
        relatedEntityId:
            r.relatedEntityId.isEmpty ? null : r.relatedEntityId,
        createdAtMs: r.createdAtMs,
        readAtMs: r.readAtMs < 0 ? null : r.readAtMs,
        dismissed: r.dismissed,
      );
}
