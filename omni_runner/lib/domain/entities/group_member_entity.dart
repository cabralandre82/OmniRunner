import 'package:equatable/equatable.dart';

/// Role of a group member, determining their permissions.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum GroupRole {
  /// Full control: edit group, promote/demote, ban, delete, create goals.
  admin,

  /// Approve requests (closed groups), remove members, create goals.
  moderator,

  /// Participate in goals, contribute sessions, leave.
  member,
}

/// Membership status within a group.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum GroupMemberStatus {
  /// Currently an active member.
  active,

  /// Banned by admin/mod — cannot rejoin unless unbanned.
  banned,

  /// Voluntarily left the group.
  left,
}

/// A single user's membership record within a group.
///
/// Combination of [groupId] + [userId] is unique — enforced by the repository.
///
/// Immutable value object. No logic. No behavior.
/// See `docs/SOCIAL_SPEC.md` §3.3.
final class GroupMemberEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String groupId;
  final String userId;

  /// Cached for offline display. Updated on profile changes.
  final String displayName;

  final GroupRole role;
  final GroupMemberStatus status;

  /// When the user joined the group (ms since epoch, UTC).
  final int joinedAtMs;

  const GroupMemberEntity({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.role,
    this.status = GroupMemberStatus.active,
    required this.joinedAtMs,
  });

  bool get isActive => status == GroupMemberStatus.active;
  bool get isAdmin => role == GroupRole.admin;
  bool get canModerate => role == GroupRole.admin || role == GroupRole.moderator;

  GroupMemberEntity copyWith({
    String? displayName,
    GroupRole? role,
    GroupMemberStatus? status,
  }) =>
      GroupMemberEntity(
        id: id,
        groupId: groupId,
        userId: userId,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        status: status ?? this.status,
        joinedAtMs: joinedAtMs,
      );

  @override
  List<Object?> get props => [
        id,
        groupId,
        userId,
        displayName,
        role,
        status,
        joinedAtMs,
      ];
}
