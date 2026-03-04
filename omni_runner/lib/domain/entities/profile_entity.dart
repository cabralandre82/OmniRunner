/// Onboarding funnel state stored in `profiles.onboarding_state`.
enum OnboardingState {
  newUser,
  roleSelected,
  ready;

  static OnboardingState fromString(String? s) => switch (s) {
        'ROLE_SELECTED' => OnboardingState.roleSelected,
        'READY' => OnboardingState.ready,
        _ => OnboardingState.newUser,
      };

  String toDbString() => switch (this) {
        OnboardingState.newUser => 'NEW',
        OnboardingState.roleSelected => 'ROLE_SELECTED',
        OnboardingState.ready => 'READY',
      };
}

/// Mirrors `public.profiles` in Supabase.
///
/// Immutable value object. Never contains the raw Supabase `User` —
/// use [AuthUser] for auth state, this for the Postgres row.
class ProfileEntity {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final OnboardingState onboardingState;
  final String? userRole;
  final String? createdVia;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProfileEntity({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.onboardingState = OnboardingState.newUser,
    this.userRole,
    this.createdVia,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOnboardingComplete => onboardingState == OnboardingState.ready;

  ProfileEntity copyWith({
    String? displayName,
    String? avatarUrl,
    OnboardingState? onboardingState,
    String? userRole,
  }) =>
      ProfileEntity(
        id: id,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        onboardingState: onboardingState ?? this.onboardingState,
        userRole: userRole ?? this.userRole,
        createdVia: createdVia,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  factory ProfileEntity.fromJson(Map<String, dynamic> j) => ProfileEntity(
        id: j['id'] as String,
        displayName: j['display_name'] as String? ?? 'Runner',
        avatarUrl: j['avatar_url'] as String?,
        onboardingState:
            OnboardingState.fromString(j['onboarding_state'] as String?),
        userRole: j['user_role'] as String?,
        createdVia: j['created_via'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'onboarding_state': onboardingState.toDbString(),
        if (userRole != null) 'user_role': userRole,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
