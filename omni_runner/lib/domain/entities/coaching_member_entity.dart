import 'package:equatable/equatable.dart';

/// Role of a member within a coaching group.
///
/// Distinct from social [GroupRole] (admin/moderator/member).
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
///
/// Migration mapping (Postgres → Dart):
///   'coach'       / ordinal 0 → [adminMaster]
///   'assistant'   / ordinal 1 → [assistente]
///   'athlete'     / ordinal 2 → [atleta]
///   'professor'   / ordinal 3 → [professor]   (new in 16.10.0)
///
/// Staff = admin_master | professor | assistente (can operate the ecosystem).
enum CoachingRole {
  /// Group owner (was "coach"). Full control: analytics, events, management.
  adminMaster,

  /// Support staff (was "assistant"). View analytics, create events.
  assistente,

  /// Active runner (was "athlete"). Workouts → group analytics and rankings.
  atleta,

  /// Institutional professor (new). Same power as admin_master for operations.
  professor,
}

/// Postgres string ↔ [CoachingRole] mapping.
///
/// Handles both legacy ('coach', 'assistant', 'athlete') and
/// current ('admin_master', 'professor', 'assistente', 'atleta') values.
CoachingRole coachingRoleFromString(String value) => switch (value) {
      'admin_master' || 'coach' => CoachingRole.adminMaster,
      'professor' => CoachingRole.professor,
      'assistente' || 'assistant' => CoachingRole.assistente,
      'atleta' || 'athlete' => CoachingRole.atleta,
      _ => CoachingRole.atleta,
    };

String coachingRoleToString(CoachingRole role) => switch (role) {
      CoachingRole.adminMaster => 'admin_master',
      CoachingRole.professor => 'professor',
      CoachingRole.assistente => 'assistente',
      CoachingRole.atleta => 'atleta',
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
  bool get isProfessor => role == CoachingRole.professor;
  bool get isAssistente => role == CoachingRole.assistente;
  bool get isAtleta => role == CoachingRole.atleta;

  /// admin_master, professor, or assistente — can operate the coaching ecosystem.
  bool get isStaff =>
      role == CoachingRole.adminMaster ||
      role == CoachingRole.professor ||
      role == CoachingRole.assistente;

  /// admin_master or professor — can manage members, events, and settings.
  bool get canManage =>
      role == CoachingRole.adminMaster || role == CoachingRole.professor;

  /// admin_master, professor, or assistente — can issue tokens and invites.
  bool get canIssueTokens => isStaff;

  // Legacy aliases for migration period
  @Deprecated('Use isAdminMaster instead')
  bool get isCoach => isAdminMaster;
  @Deprecated('Use isAssistente instead')
  bool get isAssistant => isAssistente;

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
