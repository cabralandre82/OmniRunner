import 'package:equatable/equatable.dart';

/// Acceptance status of a challenge invitation.
enum ParticipantStatus {
  /// Invited but has not responded yet.
  invited,

  /// Accepted the challenge.
  accepted,

  /// Declined the invitation.
  declined,

  /// Left the challenge after accepting (no penalty).
  withdrawn,
}

/// A single participant within a challenge.
///
/// Tracks their acceptance status, accumulated progress, and the
/// verified sessions they contributed.
///
/// Immutable value object. No logic. No behavior.
final class ChallengeParticipantEntity extends Equatable {
  /// User ID of the participant.
  final String userId;

  /// Display name (cached at join time for offline rendering).
  final String displayName;

  /// Current acceptance / lifecycle status.
  final ParticipantStatus status;

  /// When the user responded to the invitation (ms since epoch, UTC).
  /// Null if still [ParticipantStatus.invited].
  final int? respondedAtMs;

  /// Accumulated progress value in the goal's unit.
  ///
  /// - [ChallengeGoal.fastestAtDistance]: best elapsed time in seconds for a qualifying session
  /// - [ChallengeGoal.mostDistance]: total meters accumulated
  /// - [ChallengeGoal.bestPaceAtDistance]: best pace in seconds/km for a qualifying session
  /// - [ChallengeGoal.collectiveDistance]: individual meters contributed
  final double progressValue;

  /// IDs of verified sessions that contributed to [progressValue].
  final List<String> contributingSessionIds;

  /// Timestamp of the last session submission (ms since epoch, UTC).
  /// Used as tiebreaker: earlier finish wins on equal [progressValue].
  final int? lastSubmittedAtMs;

  /// Assessoria group ID for context. Null for cross-group challenges.
  final String? groupId;

  /// Team assignment ('A' or 'B') for team challenges. Null for 1v1/group.
  final String? team;

  const ChallengeParticipantEntity({
    required this.userId,
    required this.displayName,
    this.status = ParticipantStatus.invited,
    this.respondedAtMs,
    this.progressValue = 0.0,
    this.contributingSessionIds = const [],
    this.lastSubmittedAtMs,
    this.groupId,
    this.team,
  });

  ChallengeParticipantEntity copyWith({
    ParticipantStatus? status,
    int? respondedAtMs,
    double? progressValue,
    List<String>? contributingSessionIds,
    int? lastSubmittedAtMs,
    String? groupId,
    String? team,
  }) =>
      ChallengeParticipantEntity(
        userId: userId,
        displayName: displayName,
        status: status ?? this.status,
        respondedAtMs: respondedAtMs ?? this.respondedAtMs,
        progressValue: progressValue ?? this.progressValue,
        contributingSessionIds:
            contributingSessionIds ?? this.contributingSessionIds,
        lastSubmittedAtMs: lastSubmittedAtMs ?? this.lastSubmittedAtMs,
        groupId: groupId ?? this.groupId,
        team: team ?? this.team,
      );

  @override
  List<Object?> get props => [
        userId,
        displayName,
        status,
        respondedAtMs,
        progressValue,
        contributingSessionIds,
        lastSubmittedAtMs,
        groupId,
        team,
      ];
}
