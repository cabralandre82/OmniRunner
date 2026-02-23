import 'package:equatable/equatable.dart';

/// A private coaching group managed by a coach (assessor).
///
/// Coaching groups are distinct from social [GroupEntity]:
/// - Always owned by a single coach (`coachUserId`).
/// - Members have coaching-specific roles (coach, assistant, athlete).
/// - Designed for professional training workflows (analytics, events, rankings).
///
/// Immutable value object. See Phase 16 — Assessoria Mode.
final class CoachingGroupEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  /// Display name (3–80 characters).
  final String name;

  /// Group logo URL. Null if not set.
  final String? logoUrl;

  /// User ID of the coach who owns this group.
  final String coachUserId;

  /// Description of the coaching group (0–500 characters).
  final String description;

  /// City where the group is based. Empty if not specified.
  final String city;

  /// Short alphanumeric code for shareable invite links.
  /// Link format: `https://omnirunner.app/invite/{inviteCode}`
  final String? inviteCode;

  /// Whether the invite code is active and accepting new members.
  final bool inviteEnabled;

  /// When the group was created (ms since epoch, UTC).
  final int createdAtMs;

  const CoachingGroupEntity({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.coachUserId,
    this.description = '',
    this.city = '',
    this.inviteCode,
    this.inviteEnabled = true,
    required this.createdAtMs,
  });

  /// Full invite link for sharing.
  String? get inviteLink =>
      inviteCode != null ? 'https://omnirunner.app/invite/$inviteCode' : null;

  CoachingGroupEntity copyWith({
    String? name,
    String? logoUrl,
    String? description,
    String? city,
    String? inviteCode,
    bool? inviteEnabled,
  }) =>
      CoachingGroupEntity(
        id: id,
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        coachUserId: coachUserId,
        description: description ?? this.description,
        city: city ?? this.city,
        inviteCode: inviteCode ?? this.inviteCode,
        inviteEnabled: inviteEnabled ?? this.inviteEnabled,
        createdAtMs: createdAtMs,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        logoUrl,
        coachUserId,
        description,
        city,
        inviteCode,
        inviteEnabled,
        createdAtMs,
      ];
}
