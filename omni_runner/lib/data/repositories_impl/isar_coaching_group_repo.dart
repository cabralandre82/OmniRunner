import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/coaching_group_model.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';

/// Isar implementation of [ICoachingGroupRepo].
final class IsarCoachingGroupRepo implements ICoachingGroupRepo {
  final Isar _isar;

  const IsarCoachingGroupRepo(this._isar);

  @override
  Future<void> save(CoachingGroupEntity group) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingGroupRecords
          .where()
          .groupUuidEqualTo(group.id)
          .findFirst();
      final record = _toRecord(group);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.coachingGroupRecords.put(record);
    });
  }

  @override
  Future<void> update(CoachingGroupEntity group) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.coachingGroupRecords
          .where()
          .groupUuidEqualTo(group.id)
          .findFirst();

      final record = _toRecord(group);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.coachingGroupRecords.put(record);
    });
  }

  @override
  Future<CoachingGroupEntity?> getById(String id) async {
    final record = await _isar.coachingGroupRecords
        .where()
        .groupUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<CoachingGroupEntity>> getByCoachUserId(
    String coachUserId,
  ) async {
    final records = await _isar.coachingGroupRecords
        .where()
        .coachUserIdEqualTo(coachUserId)
        .sortByCreatedAtMs()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<int> countByCoachUserId(String coachUserId) async {
    return _isar.coachingGroupRecords
        .where()
        .coachUserIdEqualTo(coachUserId)
        .count();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.coachingGroupRecords
          .where()
          .groupUuidEqualTo(id)
          .deleteAll();
    });
  }

  // ── Mappers ──

  static CoachingGroupRecord _toRecord(CoachingGroupEntity e) =>
      CoachingGroupRecord()
        ..groupUuid = e.id
        ..name = e.name
        ..logoUrl = e.logoUrl
        ..coachUserId = e.coachUserId
        ..description = e.description
        ..city = e.city
        ..inviteCode = e.inviteCode
        ..inviteEnabled = e.inviteEnabled
        ..createdAtMs = e.createdAtMs;

  static CoachingGroupEntity _toEntity(CoachingGroupRecord r) =>
      CoachingGroupEntity(
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
