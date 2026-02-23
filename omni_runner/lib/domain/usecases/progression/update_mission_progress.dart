import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

/// Result of updating mission progress after a session.
final class MissionUpdateResult {
  /// Missions whose progress was updated (but not necessarily completed).
  final List<MissionProgressEntity> updated;

  /// Missions that were completed by this session.
  final List<MissionProgressEntity> completed;

  const MissionUpdateResult({
    this.updated = const [],
    this.completed = const [],
  });
}

/// Updates progress for all active missions after a verified session.
///
/// Each [MissionCriteria] type maps to a different progress delta:
/// - [AccumulateDistance] → adds session distance
/// - [CompleteSessionCount] → increments by 1
/// - [AchievePaceTarget] → sets to 1.0 if pace target met
/// - [SingleSessionDurationTarget] → sets to 1.0 if duration met
/// - [HrZoneTime] → no-op (requires HR zone time data, future)
/// - [MaintainStreak] → reads current streak from profile
/// - [CompleteChallenges] → no-op (updated by challenge flow)
///
/// Marks completed missions and records contributing session.
/// Does NOT credit XP/Coins — that is [ClaimRewards]' job.
///
/// See `docs/PROGRESSION_SPEC.md` §7.
final class UpdateMissionProgress {
  final IMissionProgressRepo _progressRepo;

  const UpdateMissionProgress({required IMissionProgressRepo progressRepo})
      : _progressRepo = progressRepo;

  Future<MissionUpdateResult> call({
    required WorkoutSessionEntity session,
    required double sessionDistanceM,
    required int sessionMovingMs,
    required double? sessionPaceSecPerKm,
    required ProfileProgressEntity profile,
    required List<MissionEntity> activeMissionDefs,
    required int nowMs,
  }) async {
    final userId = session.userId;
    if (userId == null || userId.isEmpty) {
      return const MissionUpdateResult();
    }

    final activeProgress = await _progressRepo.getActiveByUserId(userId);
    if (activeProgress.isEmpty) return const MissionUpdateResult();

    final defMap = {for (final d in activeMissionDefs) d.id: d};

    final updated = <MissionProgressEntity>[];
    final completed = <MissionProgressEntity>[];

    for (final progress in activeProgress) {
      final def = defMap[progress.missionId];
      if (def == null) continue;
      if (def.isExpired(nowMs)) continue;
      if (progress.contributingSessionIds.contains(session.id)) continue;

      final delta = _computeDelta(
        def.criteria,
        sessionDistanceM: sessionDistanceM,
        sessionMovingMs: sessionMovingMs,
        sessionPaceSecPerKm: sessionPaceSecPerKm,
        profile: profile,
      );

      if (delta == null) continue;

      final newValue = progress.currentValue + delta;
      final newSessions = [
        ...progress.contributingSessionIds,
        session.id,
      ];

      var newProgress = progress.copyWith(
        currentValue: newValue,
        contributingSessionIds: newSessions,
      );

      if (newProgress.isCriteriaMet &&
          newProgress.status == MissionProgressStatus.active) {
        newProgress = newProgress.copyWith(
          status: MissionProgressStatus.completed,
          completedAtMs: nowMs,
          completionCount: newProgress.completionCount + 1,
        );
        completed.add(newProgress);
      }

      await _progressRepo.save(newProgress);
      updated.add(newProgress);
    }

    return MissionUpdateResult(updated: updated, completed: completed);
  }

  /// Returns the progress delta for this session, or null if the
  /// criteria type is not session-driven.
  static double? _computeDelta(
    MissionCriteria criteria, {
    required double sessionDistanceM,
    required int sessionMovingMs,
    required double? sessionPaceSecPerKm,
    required ProfileProgressEntity profile,
  }) =>
      switch (criteria) {
        AccumulateDistance() => sessionDistanceM,
        CompleteSessionCount() => 1.0,
        AchievePaceTarget(
          maxPaceSecPerKm: final maxPace,
          minDistanceM: final minD
        ) =>
          sessionDistanceM >= minD &&
                  sessionPaceSecPerKm != null &&
                  sessionPaceSecPerKm < maxPace
              ? 1.0
              : null,
        SingleSessionDurationTarget(targetMs: final t) =>
          sessionMovingMs >= t ? 1.0 : null,
        HrZoneTime() => null,
        MaintainStreak() => profile.dailyStreakCount.toDouble(),
        CompleteChallenges() => null,
      };
}
