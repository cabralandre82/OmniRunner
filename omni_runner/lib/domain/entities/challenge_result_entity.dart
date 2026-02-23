import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

/// Outcome for a single participant after a challenge completes.
enum ParticipantOutcome {
  /// Participant won (best result or met target first in 1v1).
  won,

  /// Participant lost (worse result in 1v1).
  lost,

  /// Both participants tied (equal results).
  tied,

  /// Participant completed the group challenge target.
  completedTarget,

  /// Participant contributed but did not reach the group target.
  participated,

  /// Participant withdrew or never accepted.
  didNotFinish,
}

/// A single participant's result within a challenge.
final class ParticipantResult extends Equatable {
  /// User ID.
  final String userId;

  /// Final value in the metric's unit (meters, sec/km, or ms).
  final double finalValue;

  /// Rank among participants (1-based). Null for group challenges.
  final int? rank;

  /// What happened.
  final ParticipantOutcome outcome;

  /// Coins earned from this challenge (participation + bonus).
  final int coinsEarned;

  /// IDs of verified sessions that contributed.
  final List<String> sessionIds;

  const ParticipantResult({
    required this.userId,
    required this.finalValue,
    this.rank,
    required this.outcome,
    required this.coinsEarned,
    this.sessionIds = const [],
  });

  @override
  List<Object?> get props => [
        userId,
        finalValue,
        rank,
        outcome,
        coinsEarned,
        sessionIds,
      ];
}

/// Finalized results of a completed challenge.
///
/// Created once when a challenge transitions to [ChallengeStatus.completed].
/// Immutable and append-only — never modified after creation.
///
/// See `docs/GAMIFICATION_POLICY.md` §4 for reward rules.
final class ChallengeResultEntity extends Equatable {
  /// The challenge this result belongs to.
  final String challengeId;

  /// The metric that was measured.
  final ChallengeMetric metric;

  /// Individual results for each participant, ordered by rank.
  final List<ParticipantResult> results;

  /// Total Coins distributed across all participants.
  final int totalCoinsDistributed;

  /// When the results were calculated (ms since epoch, UTC).
  final int calculatedAtMs;

  const ChallengeResultEntity({
    required this.challengeId,
    required this.metric,
    required this.results,
    required this.totalCoinsDistributed,
    required this.calculatedAtMs,
  });

  /// The winner(s). Empty if no one won (e.g. all withdrew).
  List<ParticipantResult> get winners =>
      results.where((r) => r.outcome == ParticipantOutcome.won ||
                           r.outcome == ParticipantOutcome.tied).toList();

  @override
  List<Object?> get props => [
        challengeId,
        metric,
        results,
        totalCoinsDistributed,
        calculatedAtMs,
      ];
}
