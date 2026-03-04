import 'package:isar/isar.dart';

import 'package:omni_runner/core/cache/cache_metadata_store.dart';
import 'package:omni_runner/data/models/isar/progress_model.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';

final class IsarProfileProgressRepo implements IProfileProgressRepo {
  final Isar _isar;
  final CacheMetadataStore _cacheMeta;

  IsarProfileProgressRepo(this._isar, this._cacheMeta);

  @override
  Future<ProfileProgressEntity> getByUserId(String userId) async {
    final record = await _isar.profileProgressRecords
        .where()
        .userIdEqualTo(userId)
        .findFirst();

    if (record != null) return _toEntity(record);

    final fresh = ProfileProgressEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(ProfileProgressEntity profile) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.profileProgressRecords
          .where()
          .userIdEqualTo(profile.userId)
          .findFirst();

      final record = _toRecord(profile);
      if (existing != null) record.isarId = existing.isarId;

      await _isar.profileProgressRecords.put(record);
    });
    _cacheMeta.recordCacheWriteSync('profile_progress', profile.userId);
  }

  static ProfileProgressRecord _toRecord(ProfileProgressEntity e) =>
      ProfileProgressRecord()
        ..userId = e.userId
        ..totalXp = e.totalXp
        ..seasonXp = e.seasonXp
        ..currentSeasonId = e.currentSeasonId
        ..dailyStreakCount = e.dailyStreakCount
        ..streakBest = e.streakBest
        ..lastStreakDayMs = e.lastStreakDayMs
        ..hasFreezeAvailable = e.hasFreezeAvailable
        ..weeklySessionCount = e.weeklySessionCount
        ..monthlySessionCount = e.monthlySessionCount
        ..lifetimeSessionCount = e.lifetimeSessionCount
        ..lifetimeDistanceM = e.lifetimeDistanceM
        ..lifetimeMovingMs = e.lifetimeMovingMs;

  static ProfileProgressEntity _toEntity(ProfileProgressRecord r) =>
      ProfileProgressEntity(
        userId: r.userId,
        totalXp: r.totalXp,
        seasonXp: r.seasonXp,
        currentSeasonId: r.currentSeasonId,
        dailyStreakCount: r.dailyStreakCount,
        streakBest: r.streakBest,
        lastStreakDayMs: r.lastStreakDayMs,
        hasFreezeAvailable: r.hasFreezeAvailable,
        weeklySessionCount: r.weeklySessionCount,
        monthlySessionCount: r.monthlySessionCount,
        lifetimeSessionCount: r.lifetimeSessionCount,
        lifetimeDistanceM: r.lifetimeDistanceM,
        lifetimeMovingMs: r.lifetimeMovingMs,
      );
}
