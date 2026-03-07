import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Drift implementation of [ICoachingMemberRepo].
final class DriftCoachingMemberRepo implements ICoachingMemberRepo {
  final AppDatabase _db;

  const DriftCoachingMemberRepo(this._db);

  @override
  Future<void> save(CoachingMemberEntity member) async {
    await _db.into(_db.coachingMembers).insertOnConflictUpdate(_toCompanion(member));
  }

  @override
  Future<void> update(CoachingMemberEntity member) async {
    await (_db.update(_db.coachingMembers)
          ..where((t) => t.memberUuid.equals(member.id)))
        .write(_toCompanion(member));
  }

  @override
  Future<CoachingMemberEntity?> getMember(String groupId, String userId) async {
    final row = await (_db.select(_db.coachingMembers)
          ..where((t) => t.groupId.equals(groupId) & t.userId.equals(userId)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<CoachingMemberEntity>> getByGroupId(String groupId) async {
    final rows = await (_db.select(_db.coachingMembers)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.roleOrdinal),
            (t) => OrderingTerm.asc(t.joinedAtMs),
          ]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<CoachingMemberEntity>> getByUserId(String userId) async {
    final rows = await (_db.select(_db.coachingMembers)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.asc(t.joinedAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> countByGroupId(String groupId) async {
    final count = countAll();
    final query = _db.selectOnly(_db.coachingMembers)
      ..addColumns([count])
      ..where(_db.coachingMembers.groupId.equals(groupId));
    final result = await query.getSingle();
    return result.read(count)!;
  }

  @override
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.coachingMembers)
          ..where((t) => t.memberUuid.equals(id)))
        .go();
  }

  // ── Mappers ──

  static CoachingMembersCompanion _toCompanion(CoachingMemberEntity e) =>
      CoachingMembersCompanion.insert(
        memberUuid: e.id,
        groupId: e.groupId,
        userId: e.userId,
        displayName: e.displayName,
        roleOrdinal: e.role.name,
        joinedAtMs: e.joinedAtMs,
      );

  static CoachingMemberEntity _toEntity(CoachingMember r) =>
      CoachingMemberEntity(
        id: r.memberUuid,
        groupId: r.groupId,
        userId: r.userId,
        displayName: r.displayName,
        role: safeByName(CoachingRole.values, r.roleOrdinal, fallback: CoachingRole.athlete),
        joinedAtMs: r.joinedAtMs,
      );
}
