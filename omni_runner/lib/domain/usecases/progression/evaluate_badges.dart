import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';

/// Context passed to the badge evaluator containing all data
/// needed to check every [BadgeCriteria] subtype.
final class BadgeEvalContext {
  final WorkoutSessionEntity session;
  final ProfileProgressEntity profile;

  /// Average pace (sec/km) of this session. Null if distance is 0.
  final double? sessionPaceSecPerKm;

  /// Duration of this session in milliseconds.
  final int sessionMovingMs;

  /// Distance of this session in meters.
  final double sessionDistanceM;

  /// Whether this session set a new personal record for pace.
  final bool isNewPacePr;

  /// Local hour (0–23) when the session started.
  final int sessionStartHourLocal;

  const BadgeEvalContext({
    required this.session,
    required this.profile,
    this.sessionPaceSecPerKm,
    required this.sessionMovingMs,
    required this.sessionDistanceM,
    this.isNewPacePr = false,
    required this.sessionStartHourLocal,
  });
}

/// Evaluates all badge definitions against the current session + profile
/// and returns newly unlocked badges.
///
/// Pure evaluation logic — never re-locks. Checks [IBadgeAwardRepo]
/// for existing unlocks to avoid duplicates.
///
/// See `docs/PROGRESSION_SPEC.md` §5.
final class EvaluateBadges {
  final IBadgeAwardRepo _awardRepo;

  const EvaluateBadges({required IBadgeAwardRepo awardRepo})
      : _awardRepo = awardRepo;

  /// Returns list of [BadgeAwardEntity] for badges newly unlocked.
  /// Empty list if nothing new was unlocked.
  Future<List<BadgeAwardEntity>> call({
    required List<BadgeEntity> catalog,
    required BadgeEvalContext ctx,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final awards = <BadgeAwardEntity>[];
    final userId = ctx.session.userId;
    if (userId == null || userId.isEmpty) return awards;

    for (final badge in catalog) {
      if (await _awardRepo.isUnlocked(userId, badge.id)) continue;
      if (!_matches(badge.criteria, ctx)) continue;

      final award = BadgeAwardEntity(
        id: uuidGenerator(),
        userId: userId,
        badgeId: badge.id,
        triggerSessionId: ctx.session.id,
        unlockedAtMs: nowMs,
        xpAwarded: badge.xpReward,
        coinsAwarded: badge.coinsReward,
      );
      await _awardRepo.save(award);
      awards.add(award);
    }
    return awards;
  }

  /// Pure criteria matching — no I/O.
  static bool _matches(BadgeCriteria criteria, BadgeEvalContext ctx) =>
      switch (criteria) {
        SingleSessionDistance(thresholdM: final t) =>
          ctx.sessionDistanceM >= t,
        LifetimeDistance(thresholdM: final t) =>
          ctx.profile.lifetimeDistanceM >= t,
        SessionCount(count: final c) =>
          ctx.profile.lifetimeSessionCount >= c,
        PaceBelow(maxPaceSecPerKm: final max, minDistanceM: final minD) =>
          ctx.sessionDistanceM >= minD &&
              ctx.sessionPaceSecPerKm != null &&
              ctx.sessionPaceSecPerKm! < max,
        PersonalRecordPace(minDistanceM: final minD) =>
          ctx.isNewPacePr && ctx.sessionDistanceM >= minD,
        SingleSessionDuration(thresholdMs: final t) =>
          ctx.sessionMovingMs >= t,
        LifetimeDuration(thresholdMs: final t) =>
          ctx.profile.lifetimeMovingMs >= t,
        DailyStreak(days: final d) =>
          ctx.profile.dailyStreakCount >= d,
        ChallengesCompleted(count: final _) =>
          false, // Evaluated by challenge flow, not session flow
        ConsecutiveWins(count: final _) =>
          false, // Evaluated by challenge flow, not session flow
        GroupLeader(minParticipants: final _) =>
          false, // Evaluated by challenge flow, not session flow
        SessionBeforeHour(hourLocal: final h) =>
          ctx.sessionStartHourLocal < h,
        SessionAfterHour(hourLocal: final h) =>
          ctx.sessionStartHourLocal >= h,
      };
}
