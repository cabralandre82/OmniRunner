import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';

/// In-memory profile datasource for offline/mock mode.
///
/// Creates a stub profile from [UserIdentityProvider] on first access.
class MockProfileDataSource implements IProfileRepo {
  final UserIdentityProvider _identity;
  ProfileEntity? _cached;

  MockProfileDataSource({required UserIdentityProvider identity})
      : _identity = identity;

  @override
  Future<ProfileEntity?> getMyProfile() async {
    _cached ??= ProfileEntity(
      id: _identity.userId,
      displayName: _identity.displayName,
      onboardingState: OnboardingState.ready,
      createdVia: 'OTHER',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    return _cached;
  }

  @override
  Future<ProfileEntity> upsertMyProfile(ProfilePatch patch) async {
    final current = await getMyProfile();
    _cached = current!.copyWith(
      displayName: patch.displayName,
      avatarUrl: patch.avatarUrl,
    );
    return _cached!;
  }
}
