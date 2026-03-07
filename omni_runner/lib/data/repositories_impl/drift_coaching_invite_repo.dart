import 'package:drift/drift.dart';
import 'package:omni_runner/core/utils/safe_enum.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';

/// Drift implementation of [ICoachingInviteRepo].
final class DriftCoachingInviteRepo implements ICoachingInviteRepo {
  final AppDatabase _db;

  const DriftCoachingInviteRepo(this._db);

  @override
  Future<void> save(CoachingInviteEntity invite) async {
    await _db.into(_db.coachingInvites).insertOnConflictUpdate(_toCompanion(invite));
  }

  @override
  Future<void> update(CoachingInviteEntity invite) async {
    await (_db.update(_db.coachingInvites)
          ..where((t) => t.inviteUuid.equals(invite.id)))
        .write(_toCompanion(invite));
  }

  @override
  Future<CoachingInviteEntity?> getById(String id) async {
    final row = await (_db.select(_db.coachingInvites)
          ..where((t) => t.inviteUuid.equals(id)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<CoachingInviteEntity>> getPendingByUserId(String userId) async {
    final rows = await (_db.select(_db.coachingInvites)
          ..where((t) =>
              t.invitedUserId.equals(userId) &
              t.statusOrdinal.equals(CoachingInviteStatus.pending.name))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<CoachingInviteEntity>> getByGroupId(String groupId) async {
    final rows = await (_db.select(_db.coachingInvites)
          ..where((t) => t.groupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<CoachingInviteEntity?> findPending(
    String groupId,
    String userId,
  ) async {
    final row = await (_db.select(_db.coachingInvites)
          ..where((t) =>
              t.groupId.equals(groupId) &
              t.invitedUserId.equals(userId) &
              t.statusOrdinal.equals(CoachingInviteStatus.pending.name)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.coachingInvites)
          ..where((t) => t.inviteUuid.equals(id)))
        .go();
  }

  // ── Mappers ──

  static CoachingInvitesCompanion _toCompanion(CoachingInviteEntity e) =>
      CoachingInvitesCompanion.insert(
        inviteUuid: e.id,
        groupId: e.groupId,
        invitedUserId: e.invitedUserId,
        invitedByUserId: e.invitedByUserId,
        statusOrdinal: e.status.name,
        expiresAtMs: e.expiresAtMs,
        createdAtMs: e.createdAtMs,
      );

  static CoachingInviteEntity _toEntity(CoachingInvite r) =>
      CoachingInviteEntity(
        id: r.inviteUuid,
        groupId: r.groupId,
        invitedUserId: r.invitedUserId,
        invitedByUserId: r.invitedByUserId,
        status: safeByName(CoachingInviteStatus.values, r.statusOrdinal, fallback: CoachingInviteStatus.pending),
        expiresAtMs: r.expiresAtMs,
        createdAtMs: r.createdAtMs,
      );
}
