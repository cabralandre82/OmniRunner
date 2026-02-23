/// Failures specific to the social engine (friends, groups, events).
///
/// Sealed hierarchy — enables exhaustive pattern matching in BLoC.
/// See `docs/SOCIAL_SPEC.md` for business rules.
sealed class SocialFailure {
  const SocialFailure();
}

// ── Friendship ──────────────────────────────────────────────

/// A friendship or request already exists between these two users.
final class FriendshipAlreadyExists extends SocialFailure {
  final String userIdA;
  final String userIdB;
  const FriendshipAlreadyExists(this.userIdA, this.userIdB);
}

/// One user has blocked the other — no interaction allowed.
final class UserIsBlocked extends SocialFailure {
  final String blockerUserId;
  final String blockedUserId;
  const UserIsBlocked(this.blockerUserId, this.blockedUserId);
}

/// Cannot send more friend requests (limit: 50 pending).
final class FriendRequestLimitReached extends SocialFailure {
  final int limit;
  const FriendRequestLimitReached(this.limit);
}

/// Cannot add more friends (limit: 500).
final class FriendLimitReached extends SocialFailure {
  final int limit;
  const FriendLimitReached(this.limit);
}

/// Friendship not found (invalid ID or already removed).
final class FriendshipNotFound extends SocialFailure {
  final String friendshipId;
  const FriendshipNotFound(this.friendshipId);
}

/// Action requires friendship to be in a different status.
final class InvalidFriendshipStatus extends SocialFailure {
  final String friendshipId;
  final String expected;
  final String actual;
  const InvalidFriendshipStatus(this.friendshipId, this.expected, this.actual);
}

/// User tried to send a friend request to themselves.
final class CannotFriendSelf extends SocialFailure {
  const CannotFriendSelf();
}

// ── Groups ──────────────────────────────────────────────────

/// Group not found.
final class GroupNotFound extends SocialFailure {
  final String groupId;
  const GroupNotFound(this.groupId);
}

/// Group has reached its member limit.
final class GroupFull extends SocialFailure {
  final String groupId;
  final int maxMembers;
  const GroupFull(this.groupId, this.maxMembers);
}

/// User is already a member of this group.
final class AlreadyGroupMember extends SocialFailure {
  final String userId;
  final String groupId;
  const AlreadyGroupMember(this.userId, this.groupId);
}

/// User is not a member of this group.
final class NotGroupMember extends SocialFailure {
  final String userId;
  final String groupId;
  const NotGroupMember(this.userId, this.groupId);
}

/// User has reached the maximum number of groups (10).
final class GroupLimitReached extends SocialFailure {
  final int limit;
  const GroupLimitReached(this.limit);
}

/// User is banned from this group.
final class UserBannedFromGroup extends SocialFailure {
  final String userId;
  final String groupId;
  const UserBannedFromGroup(this.userId, this.groupId);
}

/// Insufficient role for the requested operation.
final class InsufficientGroupRole extends SocialFailure {
  final String userId;
  final String groupId;
  final String requiredRole;
  const InsufficientGroupRole(this.userId, this.groupId, this.requiredRole);
}

// ── Events ──────────────────────────────────────────────────

/// Event not found.
final class EventNotFound extends SocialFailure {
  final String eventId;
  const EventNotFound(this.eventId);
}

/// Event is not in the expected status.
final class InvalidEventStatus extends SocialFailure {
  final String eventId;
  final String expected;
  final String actual;
  const InvalidEventStatus(this.eventId, this.expected, this.actual);
}

/// User already joined this event.
final class AlreadyJoinedEvent extends SocialFailure {
  final String userId;
  final String eventId;
  const AlreadyJoinedEvent(this.userId, this.eventId);
}

/// Event has reached its participant limit.
final class EventFull extends SocialFailure {
  final String eventId;
  final int maxParticipants;
  const EventFull(this.eventId, this.maxParticipants);
}

/// User has reached the maximum simultaneous events (5).
final class EventLimitReached extends SocialFailure {
  final int limit;
  const EventLimitReached(this.limit);
}

/// User is not participating in this event.
final class NotEventParticipant extends SocialFailure {
  final String userId;
  final String eventId;
  const NotEventParticipant(this.userId, this.eventId);
}
