import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/coaching_invite_model.dart';
import 'package:omni_runner/domain/entities/coaching_invite_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_invite_repo.dart';

/// Isar implementation of [ICoachingInviteRepo].
final class IsarCoachingInviteRepo implements ICoachingInviteRepo {
  final Isar _isar;

  const IsarCoachingInviteRepo(this._isar);

  @override
  Future<void> save(CoachingInviteEntity invite) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingInviteRecords
          .where()
          .inviteUuidEqualTo(invite.id)
          .findFirst();
      final record = _toRecord(invite);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.coachingInviteRecords.put(record);
    });
  }

  @override
  Future<void> update(CoachingInviteEntity invite) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingInviteRecords
          .where()
          .inviteUuidEqualTo(invite.id)
          .findFirst();

      final record = _toRecord(invite);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.coachingInviteRecords.put(record);
    });
  }

  @override
  Future<CoachingInviteEntity?> getById(String id) async {
    final record = await _isar.coachingInviteRecords
        .where()
        .inviteUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<CoachingInviteEntity>> getPendingByUserId(
    String userId,
  ) async {
    final records = await _isar.coachingInviteRecords
        .where()
        .invitedUserIdEqualTo(userId)
        .filter()
        .statusOrdinalEqualTo(CoachingInviteStatus.pending.index)
        .sortByCreatedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<CoachingInviteEntity>> getByGroupId(String groupId) async {
    final records = await _isar.coachingInviteRecords
        .where()
        .groupIdEqualTo(groupId)
        .sortByCreatedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<CoachingInviteEntity?> findPending(
    String groupId,
    String userId,
  ) async {
    final records = await _isar.coachingInviteRecords
        .where()
        .groupIdEqualTo(groupId)
        .filter()
        .invitedUserIdEqualTo(userId)
        .statusOrdinalEqualTo(CoachingInviteStatus.pending.index)
        .findAll();
    return records.isEmpty ? null : _toEntity(records.first);
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.coachingInviteRecords
          .where()
          .inviteUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static CoachingInviteRecord _toRecord(CoachingInviteEntity e) =>
      CoachingInviteRecord()
        ..inviteUuid = e.id
        ..groupId = e.groupId
        ..invitedUserId = e.invitedUserId
        ..invitedByUserId = e.invitedByUserId
        ..statusOrdinal = e.status.index
        ..expiresAtMs = e.expiresAtMs
        ..createdAtMs = e.createdAtMs;

  static CoachingInviteEntity _toEntity(CoachingInviteRecord r) =>
      CoachingInviteEntity(
        id: r.inviteUuid,
        groupId: r.groupId,
        invitedUserId: r.invitedUserId,
        invitedByUserId: r.invitedByUserId,
        status: CoachingInviteStatus.values[r.statusOrdinal],
        expiresAtMs: r.expiresAtMs,
        createdAtMs: r.createdAtMs,
      );
}
