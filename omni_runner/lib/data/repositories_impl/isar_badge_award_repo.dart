import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/badge_model.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';

final class IsarBadgeAwardRepo implements IBadgeAwardRepo {
  final Isar _isar;

  const IsarBadgeAwardRepo(this._isar);

  @override
  Future<void> save(BadgeAwardEntity award) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.badgeAwardRecords
          .where()
          .awardUuidEqualTo(award.id)
          .findFirst();
      final record = _toRecord(award);
      if (existing != null) record.isarId = existing.isarId;
      await _isar.badgeAwardRecords.put(record);
    });
  }

  @override
  Future<List<BadgeAwardEntity>> getByUserId(String userId) async {
    final records = await _isar.badgeAwardRecords
        .where()
        .userIdEqualTo(userId)
        .sortByUnlockedAtMsDesc()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<bool> isUnlocked(String userId, String badgeId) async {
    final record = await _isar.badgeAwardRecords
        .where()
        .userIdEqualTo(userId)
        .filter()
        .badgeIdEqualTo(badgeId)
        .findFirst();
    return record != null;
  }

  static BadgeAwardRecord _toRecord(BadgeAwardEntity e) =>
      BadgeAwardRecord()
        ..awardUuid = e.id
        ..userId = e.userId
        ..badgeId = e.badgeId
        ..triggerSessionId = e.triggerSessionId
        ..unlockedAtMs = e.unlockedAtMs
        ..xpAwarded = e.xpAwarded
        ..coinsAwarded = e.coinsAwarded;

  static BadgeAwardEntity _toEntity(BadgeAwardRecord r) => BadgeAwardEntity(
        id: r.awardUuid,
        userId: r.userId,
        badgeId: r.badgeId,
        triggerSessionId: r.triggerSessionId,
        unlockedAtMs: r.unlockedAtMs,
        xpAwarded: r.xpAwarded,
        coinsAwarded: r.coinsAwarded,
      );
}
