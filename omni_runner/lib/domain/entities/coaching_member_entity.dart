import 'package:equatable/equatable.dart';

import 'package:omni_runner/core/logging/logger.dart';

/// Role of a member within a coaching group.
///
/// Distinct from social [GroupRole] (admin/moderator/member).
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
///
/// Canonical Postgres values (ASCII, no accents):
///   'admin_master' / ordinal 0 → [adminMaster]
///   'assistant'    / ordinal 1 → [assistant]
///   'athlete'      / ordinal 2 → [athlete]
///   'coach'        / ordinal 3 → [coach]
///
/// Staff = admin_master | coach | assistant (can operate the ecosystem).
enum CoachingRole {
  /// Group owner. Full control: analytics, events, management.
  adminMaster,

  /// Support staff. View analytics, create events.
  assistant,

  /// Active runner. Workouts → group analytics and rankings.
  athlete,

  /// Trainer/professor. Same power as admin_master for operations.
  coach,
}

/// Postgres string ↔ [CoachingRole] mapping.
///
/// Handles both legacy and canonical values for safe migration.
/// Unknown values fall back to [CoachingRole.athlete] but are logged
/// as warnings so they surface in DevTools/Sentry.
CoachingRole coachingRoleFromString(String value) => switch (value) {
      'admin_master' => CoachingRole.adminMaster,
      'coach' || 'professor' => CoachingRole.coach,
      'assistant' || 'assistente' => CoachingRole.assistant,
      'athlete' || 'atleta' => CoachingRole.athlete,
      _ => () {
          AppLogger.warn(
            'Unknown coaching role "$value" — falling back to athlete',
            tag: 'CoachingRole',
          );
          return CoachingRole.athlete;
        }(),
    };

String coachingRoleToString(CoachingRole role) => switch (role) {
      CoachingRole.adminMaster => 'admin_master',
      CoachingRole.coach => 'coach',
      CoachingRole.assistant => 'assistant',
      CoachingRole.athlete => 'athlete',
    };

/// A user's membership record within a coaching group.
///
/// The combination of [groupId] + [userId] is unique — enforced by the repo.
/// Separate from social [GroupMemberEntity] to support coaching-specific
/// roles and workflows.
///
/// Immutable value object. See Phase 16 — Assessoria Mode.
final class CoachingMemberEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String userId;
  final String groupId;

  /// Cached for offline display.
  final String displayName;

  final CoachingRole role;

  /// When the user joined the coaching group (ms since epoch, UTC).
  final int joinedAtMs;

  const CoachingMemberEntity({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.displayName,
    required this.role,
    required this.joinedAtMs,
  });

  bool get isAdminMaster => role == CoachingRole.adminMaster;
  bool get isCoach => role == CoachingRole.coach;
  bool get isAssistant => role == CoachingRole.assistant;
  bool get isAthlete => role == CoachingRole.athlete;

  /// admin_master, coach, or assistant — can operate the coaching ecosystem.
  bool get isStaff =>
      role == CoachingRole.adminMaster ||
      role == CoachingRole.coach ||
      role == CoachingRole.assistant;

  /// admin_master or coach — can manage members, events, and settings.
  bool get canManage =>
      role == CoachingRole.adminMaster || role == CoachingRole.coach;

  /// admin_master, coach, or assistant — can issue tokens and invites.
  bool get canIssueTokens => isStaff;

  CoachingMemberEntity copyWith({
    String? displayName,
    CoachingRole? role,
  }) =>
      CoachingMemberEntity(
        id: id,
        userId: userId,
        groupId: groupId,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        joinedAtMs: joinedAtMs,
      );

  @override
  List<Object?> get props => [
        id,
        userId,
        groupId,
        displayName,
        role,
        joinedAtMs,
      ];
}
