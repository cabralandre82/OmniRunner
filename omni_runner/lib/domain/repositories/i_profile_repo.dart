import 'package:omni_runner/domain/entities/profile_entity.dart';

/// Patch object for profile updates.
/// Only non-null fields are sent to the backend.
class ProfilePatch {
  final String? displayName;
  final String? avatarUrl;

  const ProfilePatch({this.displayName, this.avatarUrl});
}

/// Repository for the authenticated user's profile row (`public.profiles`).
abstract interface class IProfileRepo {
  /// Fetch the current user's profile. Returns null if no row exists yet.
  Future<ProfileEntity?> getMyProfile();

  /// Upsert the current user's profile with the given patch.
  /// The `id` is always `auth.uid()` — never accepted from the caller.
  Future<ProfileEntity> upsertMyProfile(ProfilePatch patch);
}
