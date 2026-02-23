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

    // 7. Extract metric value.
    final metricValue = _extractMetric(
      challenge.rules.metric,
      totalDistanceM,
      avgPaceSecPerKm,
      movingMs,
    );

    // 8. Submit to challenge.
    try {
      await _submitRun.call(
        challengeId: challenge.id,
        userId: userId,
        session: session,
        metricValue: metricValue,
      );
    } on Exception {
      return _rejected(
        session, challenge, userId, totalDistanceM, hasHr, nowMs,
        BindingRejectionReason.alreadySubmitted,
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

  static double _extractMetric(
    ChallengeMetric metric,
    double totalDistanceM,
    double? avgPaceSecPerKm,
    int movingMs,
  ) =>
      switch (metric) {
        ChallengeMetric.distance => totalDistanceM,
        ChallengeMetric.pace => avgPaceSecPerKm ?? 0.0,
        ChallengeMetric.time => movingMs.toDouble(),
      };

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
