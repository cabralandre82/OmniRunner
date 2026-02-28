import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/challenge_run_binding_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/submit_run_to_challenge.dart';

/// Dispatches a finished session to all active challenges the user
/// is participating in.
///
/// Called after [FinishSession] completes. For each active challenge:
/// 1. Validates the session against challenge rules.
/// 2. If valid, delegates to [SubmitRunToChallenge].
/// 3. Produces a [ChallengeRunBindingEntity] recording the outcome.
///
/// Never throws — collects all bindings (accepted + rejected) and
/// returns them so the caller can log/display results.
///
/// Conforms to [O4]: single `call()` method.
final class PostSessionChallengeDispatcher {
  final IChallengeRepo _challengeRepo;
  final SubmitRunToChallenge _submitRun;

  const PostSessionChallengeDispatcher({
    required IChallengeRepo challengeRepo,
    required SubmitRunToChallenge submitRun,
  })  : _challengeRepo = challengeRepo,
        _submitRun = submitRun;

  /// Evaluates and submits [session] to all eligible active challenges.
  ///
  /// [metrics] provides the computed session values:
  /// - `totalDistanceM`
  /// - `avgPaceSecPerKm`
  /// - `movingMs`
  ///
  /// Returns one [ChallengeRunBindingEntity] per active challenge.
  Future<List<ChallengeRunBindingEntity>> call({
    required WorkoutSessionEntity session,
    required double totalDistanceM,
    double? avgPaceSecPerKm,
    required int movingMs,
    required int nowMs,
  }) async {
    final userId = session.userId;
    if (userId == null || userId.isEmpty) return const [];

    final challenges = await _challengeRepo.getByUserId(userId);
    final active = challenges
        .where((c) => c.status == ChallengeStatus.active)
        .toList();

    if (active.isEmpty) return const [];

    final bindings = <ChallengeRunBindingEntity>[];

    for (final challenge in active) {
      final binding = await _evaluateAndSubmit(
        challenge: challenge,
        session: session,
        userId: userId,
        totalDistanceM: totalDistanceM,
        avgPaceSecPerKm: avgPaceSecPerKm,
        movingMs: movingMs,
        nowMs: nowMs,
      );
      bindings.add(binding);
    }

    return bindings;
  }

  Future<ChallengeRunBindingEntity> _evaluateAndSubmit({
    required ChallengeEntity challenge,
    required WorkoutSessionEntity session,
    required String userId,
    required double totalDistanceM,
    required double? avgPaceSecPerKm,
    required int movingMs,
    required int nowMs,
  }) async {
    final hasHr = session.avgBpm != null;

    // 1. Session must be completed.
    if (session.status != WorkoutStatus.completed) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.notCompleted,
      );
    }

    // 2. Anti-cheat: session must be verified.
    if (!session.isVerified) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.notVerified,
      );
    }

    // 3. Distance minimum.
    if (totalDistanceM < challenge.rules.minSessionDistanceM) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.belowMinDistance,
      );
    }

    // 3b. For target-based goals the athlete must complete the full target distance.
    final requiresTarget =
        challenge.rules.goal == ChallengeGoal.fastestAtDistance ||
        challenge.rules.goal == ChallengeGoal.bestPaceAtDistance;
    final target = challenge.rules.target;
    if (requiresTarget && target != null && target > 0 && totalDistanceM < target) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.belowTargetDistance,
      );
    }

    // 4. Within challenge window.
    if (challenge.startsAtMs != null && challenge.endsAtMs != null) {
      final sessionEnd = session.endTimeMs ?? nowMs;
      if (sessionEnd < challenge.startsAtMs! ||
          session.startTimeMs > challenge.endsAtMs!) {
        return _rejected(
          session, challenge, userId, totalDistanceM, hasHr, nowMs,
          BindingRejectionReason.outsideWindow,
        );
      }
    }

    // 5. Strict anti-cheat: require HR data.
    if (challenge.rules.antiCheatPolicy ==
            ChallengeAntiCheatPolicy.strict &&
        !hasHr) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.missingHeartRate,
      );
    }

    // 6. Already submitted? (check participant's contributing list)
    final participant = challenge.participants
        .where((p) => p.userId == userId)
        .firstOrNull;
    if (participant == null ||
        participant.status != ParticipantStatus.accepted) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.notCompleted,
      );
    }
    if (participant.contributingSessionIds.contains(session.id)) {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.alreadySubmitted,
      );
    }

    // 7. Extract progress value based on goal type.
    final metricValue = _extractProgressValue(
      challenge.rules.goal,
      totalDistanceM,
      avgPaceSecPerKm,
      movingMs,
      (session.endTimeMs ?? nowMs) - session.startTimeMs,
      challenge.rules.target,
    );

    // 8. Submit to challenge.
    try {
      await _submitRun.call(
        challengeId: challenge.id,
        userId: userId,
        session: session,
        metricValue: metricValue,
      );
    } on SessionAlreadySubmitted {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.alreadySubmitted,
      );
    } on GamificationFailure {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.submitFailed,
      );
    } on Exception {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.submitFailed,
      );
    }

    return ChallengeRunBindingEntity(
      sessionId: session.id,
      challengeId: challenge.id,
      userId: userId,
      accepted: true,
      metricValue: metricValue,
      sessionDistanceM: totalDistanceM,
      sessionVerified: session.isVerified,
      sessionIntegrityFlags: session.integrityFlags,
      sessionHadHr: hasHr,
      evaluatedAtMs: nowMs,
    );
  }

  /// For [fastestAtDistance], if the runner exceeded the target distance,
  /// scale elapsed time proportionally so nobody is penalized for running
  /// farther than required.  e.g. 12 km in 60 min → 10 km ≈ 50 min.
  static double _extractProgressValue(
    ChallengeGoal goal,
    double totalDistanceM,
    double? avgPaceSecPerKm,
    int movingMs,
    int elapsedMs,
    double? target,
  ) =>
      switch (goal) {
        ChallengeGoal.fastestAtDistance => _scaleTimeToTarget(
            elapsedMs.toDouble() / 1000.0, totalDistanceM, target),
        ChallengeGoal.mostDistance => totalDistanceM,
        ChallengeGoal.bestPaceAtDistance => avgPaceSecPerKm ?? 0.0,
        ChallengeGoal.collectiveDistance => totalDistanceM,
      };

  static double _scaleTimeToTarget(
    double elapsedSec,
    double totalDistanceM,
    double? target,
  ) {
    if (target == null || target <= 0 || totalDistanceM <= target) {
      return elapsedSec;
    }
    return elapsedSec * (target / totalDistanceM);
  }

  static ChallengeRunBindingEntity _rejected(
    WorkoutSessionEntity session,
    ChallengeEntity challenge,
    String userId,
    double distanceM,
    bool hasHr,
    int nowMs,
    BindingRejectionReason reason,
  ) =>
      ChallengeRunBindingEntity(
        sessionId: session.id,
        challengeId: challenge.id,
        userId: userId,
        accepted: false,
        rejectionReason: reason,
        sessionDistanceM: distanceM,
        sessionVerified: session.isVerified,
        sessionIntegrityFlags: session.integrityFlags,
        sessionHadHr: hasHr,
        evaluatedAtMs: nowMs,
      );
}
