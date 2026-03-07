// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/coaching_member_model.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';

/// Isar implementation of [ICoachingMemberRepo].
final class IsarCoachingMemberRepo implements ICoachingMemberRepo {
  final Isar _isar;

  const IsarCoachingMemberRepo(this._isar);

  @override
  Future<void> save(CoachingMemberEntity member) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingMemberRecords
          .where()
          .memberUuidEqualTo(member.id)
          .findFirst();
      final record = _toRecord(member);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.coachingMemberRecords.put(record);
    });
  }

  @override
  Future<void> update(CoachingMemberEntity member) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingMemberRecords
          .where()
          .memberUuidEqualTo(member.id)
          .findFirst();

      final record = _toRecord(member);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.coachingMemberRecords.put(record);
    });
  }

  @override
  Future<CoachingMemberEntity?> getMember(
    String groupId,
    String userId,
  ) async {
    final record = await _isar.coachingMemberRecords
        .where()
        .groupIdUserIdEqualTo(groupId, userId)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<CoachingMemberEntity>> getByGroupId(String groupId) async {
    final records = await _isar.coachingMemberRecords
        .where()
        .groupIdEqualTo(groupId)
        .sortByRoleOrdinal()
        .thenByJoinedAtMs()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<CoachingMemberEntity>> getByUserId(String userId) async {
    final records = await _isar.coachingMemberRecords
        .where()
        .userIdEqualTo(userId)
        .sortByJoinedAtMs()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<int> countByGroupId(String groupId) async {
    return _isar.coachingMemberRecords
        .where()
        .groupIdEqualTo(groupId)
        .count();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.coachingMemberRecords
          .where()
          .memberUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static CoachingMemberRecord _toRecord(CoachingMemberEntity e) =>
      CoachingMemberRecord()
        ..memberUuid = e.id
        ..groupId = e.groupId
        ..userId = e.userId
        ..displayName = e.displayName
        ..roleOrdinal = e.role.index
        ..joinedAtMs = e.joinedAtMs;

  static CoachingMemberEntity _toEntity(CoachingMemberRecord r) =>
      CoachingMemberEntity(
        id: r.memberUuid,
        groupId: r.groupId,
        userId: r.userId,
        displayName: r.displayName,
        role: CoachingRole.values[r.roleOrdinal],
        joinedAtMs: r.joinedAtMs,
      );
}
