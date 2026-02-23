/// Failures specific to the coaching (assessoria) engine.
///
/// Sealed hierarchy — enables exhaustive pattern matching in BLoC.
/// See Phase 16 — Assessoria Mode.
sealed class CoachingFailure {
  const CoachingFailure();
}

// ── Group ──────────────────────────────────────────────────

/// Coaching group not found.
final class CoachingGroupNotFound extends CoachingFailure {
  final String groupId;
  const CoachingGroupNotFound(this.groupId);
}

/// User has reached the maximum coaching groups they can own.
final class CoachingGroupLimitReached extends CoachingFailure {
  final int limit;
  const CoachingGroupLimitReached(this.limit);
}

// ── Member ─────────────────────────────────────────────────

/// User is already a member of this coaching group.
final class AlreadyCoachingMember extends CoachingFailure {
  final String userId;
  final String groupId;
  const AlreadyCoachingMember(this.userId, this.groupId);
}

/// User is not a member of this coaching group.
final class NotCoachingMember extends CoachingFailure {
  final String userId;
  final String groupId;
  const NotCoachingMember(this.userId, this.groupId);
}

/// Cannot remove the admin_master (owner) from their own group.
final class CannotRemoveAdminMaster extends CoachingFailure {
  final String groupId;
  const CannotRemoveAdminMaster(this.groupId);
}

/// Legacy alias for backward compatibility.
@Deprecated('Use CannotRemoveAdminMaster instead')
typedef CannotRemoveCoach = CannotRemoveAdminMaster;

/// Caller does not have the required role for this operation.
final class InsufficientCoachingRole extends CoachingFailure {
  final String userId;
  final String groupId;
  final String requiredRole;
  const InsufficientCoachingRole(this.userId, this.groupId, this.requiredRole);
}

// ── Switch Assessoria ─────────────────────────────────────

/// Server-side assessoria switch failed (RPC error).
final class SwitchAssessoriaFailed extends CoachingFailure {
  final String targetGroupId;
  final String reason;
  const SwitchAssessoriaFailed(this.targetGroupId, this.reason);
}

// ── Invite ─────────────────────────────────────────────────

/// Invite not found.
final class CoachingInviteNotFound extends CoachingFailure {
  final String inviteId;
  const CoachingInviteNotFound(this.inviteId);
}

/// A pending invite already exists for this user in this group.
final class CoachingInviteAlreadyExists extends CoachingFailure {
  final String userId;
  final String groupId;
  const CoachingInviteAlreadyExists(this.userId, this.groupId);
}

/// Invite has expired and can no longer be accepted.
final class CoachingInviteExpired extends CoachingFailure {
  final String inviteId;
  const CoachingInviteExpired(this.inviteId);
}

/// Invite is not in the expected status for this operation.
final class InvalidCoachingInviteStatus extends CoachingFailure {
  final String inviteId;
  final String expected;
  final String actual;
  const InvalidCoachingInviteStatus(
      this.inviteId, this.expected, this.actual);
}

// ── Token Intent ──────────────────────────────────────────

/// Token intent operation failed (create or consume via Edge Function).
final class TokenIntentFailed extends CoachingFailure {
  final String reason;
  const TokenIntentFailed(this.reason);
}
