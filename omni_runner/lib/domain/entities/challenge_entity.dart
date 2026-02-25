import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

/// Lifecycle status of a challenge.
enum ChallengeStatus {
  /// Created by initiator, awaiting participant acceptance.
  pending,

  /// All required participants accepted; window is active.
  active,

  /// Window elapsed; results being calculated.
  completing,

  /// Finished — results and rewards distributed.
  completed,

  /// Cancelled by creator before it became active.
  cancelled,

  /// Expired — not enough participants accepted before deadline.
  expired,
}

/// Type of challenge.
enum ChallengeType {
  /// Head-to-head between exactly 2 participants.
  oneVsOne,

  /// Group challenge with 2–50 participants.
  group,

  /// Team vs team: assessoria A vs assessoria B.
  /// Each athlete pays the same entry_fee_coins.
  /// Winning team's pool is split equally among its members.
  teamVsTeam,
}

/// The aggregate root of the gamification challenge domain.
///
/// Immutable value object. All mutations produce a new instance via [copyWith].
/// Domain-pure — no Flutter or platform imports.
///
/// See `docs/GAMIFICATION_POLICY.md` §4 for store-safe rules.
final class ChallengeEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  /// User ID of the challenge creator.
  final String creatorUserId;

  /// Current lifecycle status.
  final ChallengeStatus status;

  /// 1v1 or group.
  final ChallengeType type;

  /// Immutable ruleset defined at creation time.
  final ChallengeRulesEntity rules;

  /// Ordered list of participants (creator is always first).
  final List<ChallengeParticipantEntity> participants;

  /// When the challenge was created (ms since epoch, UTC).
  final int createdAtMs;

  /// When the challenge window actually started (ms since epoch, UTC).
  /// Null if still [ChallengeStatus.pending].
  final int? startsAtMs;

  /// When the challenge window ends (ms since epoch, UTC).
  /// Computed as `startsAtMs + rules.windowMs` when the window opens.
  final int? endsAtMs;

  /// Human-readable title set by creator. Optional.
  final String? title;

  /// Group ID of team A (creator's assessoria). Only for [ChallengeType.teamVsTeam].
  final String? teamAGroupId;

  /// Group ID of team B (invited assessoria). Only for [ChallengeType.teamVsTeam].
  final String? teamBGroupId;

  /// Name of team A's assessoria (cached for display).
  final String? teamAGroupName;

  /// Name of team B's assessoria (cached for display).
  final String? teamBGroupName;

  /// Deadline (ms epoch) by which all participants must accept (group mode).
  final int? acceptDeadlineMs;

  const ChallengeEntity({
    required this.id,
    required this.creatorUserId,
    required this.status,
    required this.type,
    required this.rules,
    required this.participants,
    required this.createdAtMs,
    this.startsAtMs,
    this.endsAtMs,
    this.title,
    this.teamAGroupId,
    this.teamBGroupId,
    this.teamAGroupName,
    this.teamBGroupName,
    this.acceptDeadlineMs,
  });

  /// Whether the challenge window is currently open.
  bool get isWindowOpen =>
      status == ChallengeStatus.active &&
      startsAtMs != null &&
      endsAtMs != null;

  /// Number of participants who accepted.
  int get acceptedCount => participants
      .where((p) => p.status == ParticipantStatus.accepted)
      .length;

  ChallengeEntity copyWith({
    ChallengeStatus? status,
    List<ChallengeParticipantEntity>? participants,
    int? startsAtMs,
    int? endsAtMs,
    String? teamBGroupId,
    String? teamBGroupName,
  }) =>
      ChallengeEntity(
        id: id,
        creatorUserId: creatorUserId,
        status: status ?? this.status,
        type: type,
        rules: rules,
        participants: participants ?? this.participants,
        createdAtMs: createdAtMs,
        startsAtMs: startsAtMs ?? this.startsAtMs,
        endsAtMs: endsAtMs ?? this.endsAtMs,
        title: title,
        teamAGroupId: teamAGroupId,
        teamBGroupId: teamBGroupId ?? this.teamBGroupId,
        teamAGroupName: teamAGroupName,
        teamBGroupName: teamBGroupName ?? this.teamBGroupName,
        acceptDeadlineMs: acceptDeadlineMs,
      );

  @override
  List<Object?> get props => [
        id,
        creatorUserId,
        status,
        type,
        rules,
        participants,
        createdAtMs,
        startsAtMs,
        endsAtMs,
        title,
        teamAGroupId,
        teamBGroupId,
        teamAGroupName,
        teamBGroupName,
        acceptDeadlineMs,
      ];
}
