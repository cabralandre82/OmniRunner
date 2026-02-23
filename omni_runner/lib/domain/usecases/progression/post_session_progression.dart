import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/usecases/progression/award_xp_for_workout.dart';
import 'package:omni_runner/domain/usecases/progression/claim_rewards.dart';
import 'package:omni_runner/domain/usecases/progression/evaluate_badges.dart';
import 'package:omni_runner/domain/usecases/progression/update_mission_progress.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';

/// Aggregate result of the entire post-session progression pipeline.
final class ProgressionResult {
  final XpAwardResult xpResult;
  final List<BadgeAwardEntity> badgesUnlocked;
  final List<MissionProgressEntity> missionsCompleted;
  final ClaimResult claimResult;

  const ProgressionResult({
    required this.xpResult,
    this.badgesUnlocked = const [],
    this.missionsCompleted = const [],
    required this.claimResult,
  });

  int get totalXp =>
      (xpResult.awarded ? xpResult.xpAwarded : 0) +
      claimResult.totalXpCredited;

  int get totalCoins => claimResult.totalCoinsCredited;
}

/// Orchestrates the full progression pipeline after a workout finishes.
///
/// Pipeline (order matters):
///   1. Award session XP (with daily cap)
///   2. Evaluate and unlock badges
///   3. Update mission progress
///   4. Claim rewards for badges + completed missions (with bonus cap)
///
/// Each step is idempotent — re-running with the same session is safe.
/// Failures in one step do not block subsequent steps (fire-through).
///
/// Never throws — catches all exceptions and logs them.
final class PostSessionProgression {
  static const _tag = 'PostSessionProgression';

  final AwardXpForWorkout _awardXp;
  final EvaluateBadges _evaluateBadges;
  final UpdateMissionProgress _updateMissions;
  final ClaimRewards _claimRewards;
  final IProfileProgressRepo _profileRepo;

  /// Badge catalog — injected so it can be swapped for testing.
  final List<BadgeEntity> badgeCatalog;

  /// Active mission definitions — injected for the same reason.
  final List<MissionEntity> Function() activeMissionDefs;

  const PostSessionProgression({
    required AwardXpForWorkout awardXp,
    required EvaluateBadges evaluateBadges,
    required UpdateMissionProgress updateMissions,
    required ClaimRewards claimRewards,
    required IProfileProgressRepo profileRepo,
    this.badgeCatalog = const [],
    required this.activeMissionDefs,
  })  : _awardXp = awardXp,
        _evaluateBadges = evaluateBadges,
        _updateMissions = updateMissions,
        _claimRewards = claimRewards,
        _profileRepo = profileRepo;

  Future<ProgressionResult> call({
    required WorkoutSessionEntity session,
    required double totalDistanceM,
    required int movingMs,
    required double? avgPaceSecPerKm,
    required bool isNewPacePr,
    required int sessionStartHourLocal,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final userId = session.userId;
    if (userId == null || userId.isEmpty) {
      AppLogger.warn('Progression skipped: no userId', tag: _tag);
      return const ProgressionResult(
        xpResult: XpAwardResult.rejected('no_user_id'),
        claimResult: ClaimResult(),
      );
    }

    // ── 1. Award session XP ──
    var xpResult = const XpAwardResult.rejected('not_run');
    try {
      xpResult = await _awardXp.call(
        session: session,
        totalDistanceM: totalDistanceM,
        movingMs: movingMs,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );
      AppLogger.info(
        'XP: awarded=${xpResult.awarded} xp=${xpResult.xpAwarded} '
        'capped=${xpResult.xpCapped}',
        tag: _tag,
      );
    } on Exception catch (e, st) {
      AppLogger.error('XP award failed', tag: _tag, error: e, stack: st);
    }

    // ── 2. Evaluate badges ──
    var badges = <BadgeAwardEntity>[];
    try {
      final profile = await _profileRepo.getByUserId(userId);
      final ctx = BadgeEvalContext(
        session: session,
        profile: profile,
        sessionPaceSecPerKm: avgPaceSecPerKm,
        sessionMovingMs: movingMs,
        sessionDistanceM: totalDistanceM,
        isNewPacePr: isNewPacePr,
        sessionStartHourLocal: sessionStartHourLocal,
      );
      badges = await _evaluateBadges.call(
        catalog: badgeCatalog,
        ctx: ctx,
        uuidGenerator: uuidGenerator,
        nowMs: nowMs,
      );
      if (badges.isNotEmpty) {
        AppLogger.info('Badges unlocked: ${badges.length}', tag: _tag);
      }
    } on Exception catch (e, st) {
      AppLogger.error('Badge evaluation failed', tag: _tag, error: e, stack: st);
    }

    // ── 3. Update mission progress ──
    var missionsCompleted = <MissionProgressEntity>[];
    try {
      final profile = await _profileRepo.getByUserId(userId);
      final missionResult = await _updateMissions.call(
        session: session,
        sessionDistanceM: totalDistanceM,
        sessionMovingMs: movingMs,
        sessionPaceSecPerKm: avgPaceSecPerKm,
        profile: profile,
        activeMissionDefs: activeMissionDefs(),
        nowMs: nowMs,
      );
      missionsCompleted = missionResult.completed;
      if (missionsCompleted.isNotEmpty) {
        AppLogger.info(
          'Missions completed: ${missionsCompleted.length}',
          tag: _tag,
        );
      }
    } on Exception catch (e, st) {
      AppLogger.error('Mission update failed', tag: _tag, error: e, stack: st);
    }

    // ── 4. Claim rewards for badges + missions ──
    var claimResult = const ClaimResult();
    if (badges.isNotEmpty || missionsCompleted.isNotEmpty) {
      try {
        final defs = activeMissionDefs();
        final defMap = {for (final d in defs) d.id: d};

        claimResult = await _claimRewards.call(
          userId: userId,
          badges: badges,
          missions: missionsCompleted,
          missionDefs: defMap,
          uuidGenerator: uuidGenerator,
          nowMs: nowMs,
        );
        AppLogger.info(
          'Claimed: xp=${claimResult.totalXpCredited} '
          'coins=${claimResult.totalCoinsCredited} '
          'capped=${claimResult.xpCapped}',
          tag: _tag,
        );
      } on Exception catch (e, st) {
        AppLogger.error('Claim rewards failed', tag: _tag, error: e, stack: st);
      }
    }

    return ProgressionResult(
      xpResult: xpResult,
      badgesUnlocked: badges,
      missionsCompleted: missionsCompleted,
      claimResult: claimResult,
    );
  }
}
