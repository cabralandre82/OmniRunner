import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';

final class DriftBadgeAwardRepo implements IBadgeAwardRepo {
  final AppDatabase _db;

  const DriftBadgeAwardRepo(this._db);

  @override
  Future<void> save(BadgeAwardEntity award) async {
    await _db.into(_db.badgeAwards).insertOnConflictUpdate(
          BadgeAwardsCompanion(
            awardUuid: Value(award.id),
            userId: Value(award.userId),
            badgeId: Value(award.badgeId),
            triggerSessionId: Value(award.triggerSessionId),
            unlockedAtMs: Value(award.unlockedAtMs),
            xpAwarded: Value(award.xpAwarded),
            coinsAwarded: Value(award.coinsAwarded),
          ),
        );
  }

  @override
  Future<List<BadgeAwardEntity>> getByUserId(String userId) async {
    final rows = await (_db.select(_db.badgeAwards)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.unlockedAtMs)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<bool> isUnlocked(String userId, String badgeId) async {
    final row = await (_db.select(_db.badgeAwards)
          ..where(
              (t) => t.userId.equals(userId) & t.badgeId.equals(badgeId)))
        .getSingleOrNull();
    return row != null;
  }

  static BadgeAwardEntity _toEntity(BadgeAward r) => BadgeAwardEntity(
        id: r.awardUuid,
        userId: r.userId,
        badgeId: r.badgeId,
        triggerSessionId: r.triggerSessionId,
        unlockedAtMs: r.unlockedAtMs,
        xpAwarded: r.xpAwarded,
        coinsAwarded: r.coinsAwarded,
      );
}
