import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';

final class DriftProfileProgressRepo implements IProfileProgressRepo {
  final AppDatabase _db;

  const DriftProfileProgressRepo(this._db);

  @override
  Future<ProfileProgressEntity> getByUserId(String userId) async {
    final row = await (_db.select(_db.profileProgresses)
          ..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();

    if (row != null) return _toEntity(row);

    final fresh = ProfileProgressEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(ProfileProgressEntity profile) async {
    await _db.into(_db.profileProgresses).insert(
          ProfileProgressesCompanion(
            userId: Value(profile.userId),
            totalXp: Value(profile.totalXp),
            seasonXp: Value(profile.seasonXp),
            currentSeasonId: Value(profile.currentSeasonId),
            dailyStreakCount: Value(profile.dailyStreakCount),
            streakBest: Value(profile.streakBest),
            lastStreakDayMs: Value(profile.lastStreakDayMs),
            hasFreezeAvailable: Value(profile.hasFreezeAvailable),
            weeklySessionCount: Value(profile.weeklySessionCount),
            monthlySessionCount: Value(profile.monthlySessionCount),
            lifetimeSessionCount: Value(profile.lifetimeSessionCount),
            lifetimeDistanceM: Value(profile.lifetimeDistanceM),
            lifetimeMovingMs: Value(profile.lifetimeMovingMs),
          ),
            mode: InsertMode.insertOrReplace,
        );
  }

  static ProfileProgressEntity _toEntity(ProfileProgress r) =>
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
