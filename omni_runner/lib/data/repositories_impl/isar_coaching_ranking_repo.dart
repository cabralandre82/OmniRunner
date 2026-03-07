// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/coaching_ranking_entry_model.dart';
import 'package:omni_runner/data/models/isar/coaching_ranking_model.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';

/// Isar implementation of [ICoachingRankingRepo].
///
/// Rankings are stored as a header ([CoachingRankingRecord]) plus
/// N entry rows ([CoachingRankingEntryRecord]) linked by [rankingId].
final class IsarCoachingRankingRepo implements ICoachingRankingRepo {
  final Isar _isar;

  const IsarCoachingRankingRepo(this._isar);

  @override
  Future<void> save(CoachingGroupRankingEntity ranking) async {
    await _isar.writeTxn(() async {
      // Upsert header.
      final existing = await _isar.coachingRankingRecords
          .where()
          .rankingUuidEqualTo(ranking.id)
          .findFirst();

      final header = _toRecord(ranking);
      if (existing != null) header.isarId = existing.isarId;
      await _isar.coachingRankingRecords.put(header);

      // Replace entries: delete old, insert new.
      await _isar.coachingRankingEntryRecords
          .where()
          .rankingIdEqualTo(ranking.id)
          .deleteAll();

      final entries = ranking.entries
          .map((e) => _entryToRecord(ranking.id, e))
          .toList();
      await _isar.coachingRankingEntryRecords.putAll(entries);
    });
  }

  @override
  Future<CoachingGroupRankingEntity?> getById(String id) async {
    final header = await _isar.coachingRankingRecords
        .where()
        .rankingUuidEqualTo(id)
        .findFirst();
    if (header == null) return null;
    return _hydrate(header);
  }

  @override
  Future<CoachingGroupRankingEntity?> getByGroupMetricPeriod(
    String groupId,
    CoachingRankingMetric metric,
    String periodKey,
  ) async {
    final headers = await _isar.coachingRankingRecords
        .where()
        .groupIdEqualTo(groupId)
        .filter()
        .metricOrdinalEqualTo(metric.index)
        .periodKeyEqualTo(periodKey)
        .sortByComputedAtMsDesc()
        .limit(1)
        .findAll();
    if (headers.isEmpty) return null;
    return _hydrate(headers.first);
  }

  @override
  Future<List<CoachingGroupRankingEntity>> getByGroupId(
    String groupId,
  ) async {
    final headers = await _isar.coachingRankingRecords
        .where()
        .groupIdEqualTo(groupId)
        .sortByComputedAtMsDesc()
        .findAll();

    final results = <CoachingGroupRankingEntity>[];
    for (final h in headers) {
      results.add(await _hydrate(h));
    }
    return results;
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.coachingRankingEntryRecords
          .where()
          .rankingIdEqualTo(id)
          .deleteAll();
      await _isar.coachingRankingRecords
          .where()
          .rankingUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Helpers ──

  Future<CoachingGroupRankingEntity> _hydrate(
    CoachingRankingRecord header,
  ) async {
    final entryRecords = await _isar.coachingRankingEntryRecords
        .where()
        .rankingIdEqualTo(header.rankingUuid)
        .sortByRank()
        .findAll();

    return CoachingGroupRankingEntity(
      id: header.rankingUuid,
      groupId: header.groupId,
      metric: CoachingRankingMetric.values[header.metricOrdinal],
      period: CoachingRankingPeriod.values[header.periodOrdinal],
      periodKey: header.periodKey,
      startsAtMs: header.startsAtMs,
      endsAtMs: header.endsAtMs,
      entries: entryRecords.map(_entryToEntity).toList(),
      computedAtMs: header.computedAtMs,
    );
  }

  // ── Header mappers ──

  static CoachingRankingRecord _toRecord(
    CoachingGroupRankingEntity e,
  ) =>
      CoachingRankingRecord()
        ..rankingUuid = e.id
        ..groupId = e.groupId
        ..metricOrdinal = e.metric.index
        ..periodOrdinal = e.period.index
        ..periodKey = e.periodKey
        ..startsAtMs = e.startsAtMs
        ..endsAtMs = e.endsAtMs
        ..computedAtMs = e.computedAtMs;

  // ── Entry mappers ──

  static CoachingRankingEntryRecord _entryToRecord(
    String rankingId,
    CoachingRankingEntryEntity e,
  ) =>
      CoachingRankingEntryRecord()
        ..rankingId = rankingId
        ..userId = e.userId
        ..displayName = e.displayName
        ..value = e.value
        ..rank = e.rank
        ..sessionCount = e.sessionCount;

  static CoachingRankingEntryEntity _entryToEntity(
    CoachingRankingEntryRecord r,
  ) =>
      CoachingRankingEntryEntity(
        userId: r.userId,
        displayName: r.displayName,
        value: r.value,
        rank: r.rank,
        sessionCount: r.sessionCount,
      );
}
