import 'dart:math' as math;

import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

/// Pool of daily mission templates.
///
/// The generator picks 2 per day from this pool using a deterministic
/// seed (UTC day ordinal + userId hash) so the same user sees the
/// same missions if the app restarts during the day.
const List<MissionEntity> _dailyPool = [
  MissionEntity(
    id: 'tpl_daily_3km',
    title: 'Corrida rápida',
    description: 'Corra pelo menos 3 km hoje',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 30,
    coinsReward: 5,
    criteria: AccumulateDistance(3000),
  ),
  MissionEntity(
    id: 'tpl_daily_5km',
    title: 'Meta de 5K',
    description: 'Corra pelo menos 5 km hoje',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 40,
    coinsReward: 8,
    criteria: AccumulateDistance(5000),
  ),
  MissionEntity(
    id: 'tpl_daily_2runs',
    title: 'Dupla do dia',
    description: 'Complete 2 corridas hoje',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 35,
    coinsReward: 5,
    criteria: CompleteSessionCount(2),
  ),
  MissionEntity(
    id: 'tpl_daily_30min',
    title: '30 minutos',
    description: 'Corra por 30 minutos em uma sessão',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 35,
    coinsReward: 7,
    criteria: SingleSessionDurationTarget(30 * 60 * 1000),
  ),
  MissionEntity(
    id: 'tpl_daily_pace',
    title: 'Ritmo forte',
    description: 'Corra abaixo de 6:00/km em sessão de 3+ km',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 50,
    coinsReward: 10,
    criteria: AchievePaceTarget(maxPaceSecPerKm: 360, minDistanceM: 3000),
  ),
  MissionEntity(
    id: 'tpl_daily_1run',
    title: 'Lace os tênis',
    description: 'Complete uma corrida hoje',
    difficulty: MissionDifficulty.easy,
    slot: MissionSlot.daily,
    xpReward: 30,
    coinsReward: 5,
    criteria: CompleteSessionCount(1),
  ),
];

/// Weekly mission templates — 2 picked per week.
const List<MissionEntity> _weeklyPool = [
  MissionEntity(
    id: 'tpl_weekly_20km',
    title: 'Semana de 20K',
    description: 'Acumule 20 km esta semana',
    difficulty: MissionDifficulty.medium,
    slot: MissionSlot.weekly,
    xpReward: 100,
    coinsReward: 20,
    criteria: AccumulateDistance(20000),
  ),
  MissionEntity(
    id: 'tpl_weekly_5runs',
    title: '5 corridas na semana',
    description: 'Complete 5 corridas esta semana',
    difficulty: MissionDifficulty.medium,
    slot: MissionSlot.weekly,
    xpReward: 80,
    coinsReward: 15,
    criteria: CompleteSessionCount(5),
  ),
  MissionEntity(
    id: 'tpl_weekly_30km',
    title: 'Semana forte',
    description: 'Acumule 30 km esta semana',
    difficulty: MissionDifficulty.medium,
    slot: MissionSlot.weekly,
    xpReward: 150,
    coinsReward: 30,
    criteria: AccumulateDistance(30000),
  ),
  MissionEntity(
    id: 'tpl_weekly_streak',
    title: 'Sem falhas',
    description: 'Mantenha 5 dias de streak',
    difficulty: MissionDifficulty.medium,
    slot: MissionSlot.weekly,
    xpReward: 120,
    coinsReward: 25,
    criteria: MaintainStreak(5),
  ),
];

/// Generates daily and weekly missions for a user.
///
/// Deterministic: same (day, userId) → same selection.
/// Skips missions that already have active progress for this user.
///
/// Called once per day (or on app launch if missions are stale).
/// See `docs/PROGRESSION_SPEC.md` §7.3.
final class CreateDailyMissions {
  final IMissionProgressRepo _progressRepo;

  const CreateDailyMissions({required IMissionProgressRepo progressRepo})
      : _progressRepo = progressRepo;

  /// Returns newly created [MissionProgressEntity] assignments.
  Future<List<MissionProgressEntity>> call({
    required String userId,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final active = await _progressRepo.getActiveByUserId(userId);
    final activeIds = active.map((p) => p.missionId).toSet();

    final results = <MissionProgressEntity>[];

    final activeDailyCount =
        active.where((p) => _isDailyTemplate(p.missionId)).length;
    if (activeDailyCount < 2) {
      final needed = 2 - activeDailyCount;
      final picked =
          _pickDeterministic(_dailyPool, userId, nowMs, activeIds, needed);
      for (final tpl in picked) {
        final progress = _createProgress(tpl, userId, uuidGenerator, nowMs);
        await _progressRepo.save(progress);
        results.add(progress);
        activeIds.add(tpl.id);
      }
    }

    final activeWeeklyCount =
        active.where((p) => _isWeeklyTemplate(p.missionId)).length;
    if (activeWeeklyCount < 2) {
      final needed = 2 - activeWeeklyCount;
      final picked =
          _pickDeterministic(_weeklyPool, userId, nowMs, activeIds, needed);
      for (final tpl in picked) {
        final progress = _createProgress(tpl, userId, uuidGenerator, nowMs);
        await _progressRepo.save(progress);
        results.add(progress);
        activeIds.add(tpl.id);
      }
    }

    return results;
  }

  static List<MissionEntity> _pickDeterministic(
    List<MissionEntity> pool,
    String userId,
    int nowMs,
    Set<String> excludeIds,
    int count,
  ) {
    final dayOrdinal = nowMs ~/ (24 * 60 * 60 * 1000);
    final seed = dayOrdinal ^ userId.hashCode;
    final rng = math.Random(seed);

    final available =
        pool.where((m) => !excludeIds.contains(m.id)).toList();
    available.shuffle(rng);

    return available.take(count).toList();
  }

  static MissionProgressEntity _createProgress(
    MissionEntity tpl,
    String userId,
    String Function() uuidGenerator,
    int nowMs,
  ) {
    final target = _targetFromCriteria(tpl.criteria);

    return MissionProgressEntity(
      id: uuidGenerator(),
      userId: userId,
      missionId: tpl.id,
      targetValue: target,
      assignedAtMs: nowMs,
    );
  }

  static double _targetFromCriteria(MissionCriteria criteria) =>
      switch (criteria) {
        AccumulateDistance(targetM: final t) => t,
        CompleteSessionCount(targetCount: final c) => c.toDouble(),
        AchievePaceTarget() => 1.0,
        SingleSessionDurationTarget() => 1.0,
        HrZoneTime() => 1.0,
        MaintainStreak(days: final d) => d.toDouble(),
        CompleteChallenges(count: final c) => c.toDouble(),
      };

  static bool _isDailyTemplate(String id) => id.startsWith('tpl_daily_');
  static bool _isWeeklyTemplate(String id) => id.startsWith('tpl_weekly_');
}
