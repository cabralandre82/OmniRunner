import 'package:equatable/equatable.dart';

/// Lifecycle of a coaching group invitation.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum CoachingInviteStatus {
  /// Invite sent, awaiting response from the invited user.
  pending,

  /// Invited user accepted — membership created.
  accepted,

  /// Invited user declined.
  declined,

  /// Invite expired (past [CoachingInviteEntity.expiresAtMs]).
  expired,
}

/// An invitation for a user to join a coaching group.
///
/// Created by a coach or assistant. The invited user accepts or declines.
/// Once expired (past [expiresAtMs]), the invite is no longer actionable.
///
/// Immutable value object. See Phase 16 — Assessoria Mode.
final class CoachingInviteEntity extends Equatable {
  /// Unique invite ID (UUID v4).
  final String id;

  final String groupId;

  /// User being invited.
  final String invitedUserId;

  /// User who sent the invite (coach or assistant).
  final String invitedByUserId;

  final CoachingInviteStatus status;

  /// When the invite expires (ms since epoch, UTC).
  final int expiresAtMs;

  /// When the invite was created (ms since epoch, UTC).
  final int createdAtMs;

  const CoachingInviteEntity({
    required this.id,
    required this.groupId,
    required this.invitedUserId,
    required this.invitedByUserId,
    required this.status,
    required this.expiresAtMs,
    required this.createdAtMs,
  });

  /// Whether the invite is still actionable given [nowMs].
  bool isActionable(int nowMs) =>
      status == CoachingInviteStatus.pending && nowMs <= expiresAtMs;

  /// Whether the invite has expired given [nowMs].
  bool hasExpired(int nowMs) => nowMs > expiresAtMs;

  CoachingInviteEntity copyWith({
    CoachingInviteStatus? status,
  }) =>
      CoachingInviteEntity(
        id: id,
        groupId: groupId,
        invitedUserId: invitedUserId,
        invitedByUserId: invitedByUserId,
        status: status ?? this.status,
        expiresAtMs: expiresAtMs,
        createdAtMs: createdAtMs,
      );

  @override
  List<Object?> get props => [
        id,
        groupId,
        invitedUserId,
        invitedByUserId,
        status,
        expiresAtMs,
        createdAtMs,
      ];
}
