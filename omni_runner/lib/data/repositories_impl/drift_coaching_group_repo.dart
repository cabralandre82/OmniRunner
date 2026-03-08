import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';

/// Drift implementation of [ICoachingGroupRepo].
final class DriftCoachingGroupRepo implements ICoachingGroupRepo {
  final AppDatabase _db;

  const DriftCoachingGroupRepo(this._db);

  @override
  Future<void> save(CoachingGroupEntity group) async {
    await _db.into(_db.coachingGroups).insert(_toCompanion(group), mode: InsertMode.insertOrReplace);
  }

  @override
  Future<void> update(CoachingGroupEntity group) async {
    await (_db.update(_db.coachingGroups)
          ..where((t) => t.groupUuid.equals(group.id)))
        .write(_toCompanion(group));
  }

  @override
  Future<CoachingGroupEntity?> getById(String id) async {
    final row = await (_db.select(_db.coachingGroups)
          ..where((t) => t.groupUuid.equals(id)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<CoachingGroupEntity>> getByCoachUserId(String coachUserId) async {
    final rows = await (_db.select(_db.coachingGroups)
          ..where((t) => t.coachUserId.equals(coachUserId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> countByCoachUserId(String coachUserId) async {
    final count = countAll();
    final query = _db.selectOnly(_db.coachingGroups)
      ..addColumns([count])
      ..where(_db.coachingGroups.coachUserId.equals(coachUserId));
    final result = await query.getSingle();
    return result.read(count)!;
  }

  @override
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.coachingGroups)
          ..where((t) => t.groupUuid.equals(id)))
        .go();
  }

  // ── Mappers ──

  static CoachingGroupsCompanion _toCompanion(CoachingGroupEntity e) =>
      CoachingGroupsCompanion.insert(
        groupUuid: e.id,
        name: e.name,
        logoUrl: Value(e.logoUrl),
        coachUserId: e.coachUserId,
        description: e.description,
        city: e.city,
        inviteCode: Value(e.inviteCode),
        inviteEnabled: e.inviteEnabled,
        createdAtMs: e.createdAtMs,
      );

  static CoachingGroupEntity _toEntity(CoachingGroup r) => CoachingGroupEntity(
        id: r.groupUuid,
        name: r.name,
        logoUrl: r.logoUrl,
        coachUserId: r.coachUserId,
        description: r.description,
        city: r.city,
        inviteCode: r.inviteCode,
        inviteEnabled: r.inviteEnabled,
        createdAtMs: r.createdAtMs,
      );
}
