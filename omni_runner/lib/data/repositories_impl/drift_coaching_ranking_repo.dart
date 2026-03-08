import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';

/// Drift implementation of [ICoachingRankingRepo].
///
/// Rankings are stored as a header ([CoachingRankings]) plus
/// N entry rows ([CoachingRankingEntries]) linked by [rankingId].
final class DriftCoachingRankingRepo implements ICoachingRankingRepo {
  final AppDatabase _db;

  const DriftCoachingRankingRepo(this._db);

  @override
  Future<void> save(CoachingGroupRankingEntity ranking) async {
    await _db.transaction(() async {
      // Upsert header.
      await _db
          .into(_db.coachingRankings)
          .insert(_headerCompanion(ranking));

      // Replace entries: delete old, insert new.
      await (_db.delete(_db.coachingRankingEntries)
            ..where((t) => t.rankingId.equals(ranking.id)))
          .go();

      await _db.batch((batch) {
        batch.insertAll(
          _db.coachingRankingEntries,
          ranking.entries
              .map((e) => _entryCompanion(ranking.id, e))
              .toList(),
            mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  @override
  Future<CoachingGroupRankingEntity?> getById(String id) async {
    final header = await (_db.select(_db.coachingRankings)
          ..where((t) => t.rankingUuid.equals(id)))
        .getSingleOrNull();
    if (header == null) return null;
    return _hydrate(header);
  }

  @override
  Future<CoachingGroupRankingEntity?> getByGroupMetricPeriod(
    String groupId,
    CoachingRankingMetric metric,
    String periodKey,
  ) async {
    final header = await (_db.select(_db.coachingRankings)
          ..where((t) =>
              t.groupId.equals(groupId) &
              t.metricOrdinal.equals(metric.name) &
              t.periodKey.equals(periodKey))
          ..orderBy([(t) => OrderingTerm.desc(t.computedAtMs)])
          ..limit(1))
        .getSingleOrNull();
    if (header == null) return null;
    return _hydrate(header);
  }

  @override
  Future<List<CoachingGroupRankingEntity>> getByGroupId(
    String groupId,
  ) async {
    final headers = await (_db.select(_db.coachingRankings)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.desc(t.computedAtMs)]))
        .get();

    final results = <CoachingGroupRankingEntity>[];
    for (final h in headers) {
      results.add(await _hydrate(h));
    }
    return results;
  }

  @override
  Future<void> deleteById(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.coachingRankingEntries)
            ..where((t) => t.rankingId.equals(id)))
          .go();
      await (_db.delete(_db.coachingRankings)
            ..where((t) => t.rankingUuid.equals(id)))
          .go();
    });
  }

  // ── Helpers ──

  Future<CoachingGroupRankingEntity> _hydrate(CoachingRanking header) async {
    final entryRows = await (_db.select(_db.coachingRankingEntries)
          ..where((t) => t.rankingId.equals(header.rankingUuid))
          ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
        .get();

    return CoachingGroupRankingEntity(
      id: header.rankingUuid,
      groupId: header.groupId,
      metric: safeByName(CoachingRankingMetric.values, header.metricOrdinal, fallback: CoachingRankingMetric.volumeDistance),
      period: safeByName(CoachingRankingPeriod.values, header.periodOrdinal, fallback: CoachingRankingPeriod.weekly),
      periodKey: header.periodKey,
      startsAtMs: header.startsAtMs,
      endsAtMs: header.endsAtMs,
      entries: entryRows.map(_entryToEntity).toList(),
      computedAtMs: header.computedAtMs,
    );
  }

  // ── Header mappers ──

  static CoachingRankingsCompanion _headerCompanion(
    CoachingGroupRankingEntity e,
  ) =>
      CoachingRankingsCompanion.insert(
        rankingUuid: e.id,
        groupId: e.groupId,
        metricOrdinal: e.metric.name,
        periodOrdinal: e.period.name,
        periodKey: e.periodKey,
        startsAtMs: e.startsAtMs,
        endsAtMs: e.endsAtMs,
        computedAtMs: e.computedAtMs,
      );

  // ── Entry mappers ──

  static CoachingRankingEntriesCompanion _entryCompanion(
    String rankingId,
    CoachingRankingEntryEntity e,
  ) =>
      CoachingRankingEntriesCompanion.insert(
        rankingId: rankingId,
        userId: e.userId,
        displayName: e.displayName,
        value: e.value,
        rank: e.rank,
        sessionCount: e.sessionCount,
      );

  static CoachingRankingEntryEntity _entryToEntity(
    CoachingRankingEntry r,
  ) =>
      CoachingRankingEntryEntity(
        userId: r.userId,
        displayName: r.displayName,
        value: r.value,
        rank: r.rank,
        sessionCount: r.sessionCount,
      );
}
