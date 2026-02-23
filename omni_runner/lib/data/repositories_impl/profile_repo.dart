import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';

/// Concrete [IProfileRepo] that delegates to a remote or mock datasource.
///
/// Wraps every call in a try/catch so callers get `null` / user-friendly
/// error strings instead of raw exceptions.
class ProfileRepo implements IProfileRepo {
  static const _tag = 'ProfileRepo';
  final IProfileRepo _ds;

  ProfileRepo({required IProfileRepo datasource}) : _ds = datasource;

  @override
  Future<ProfileEntity?> getMyProfile() async {
    try {
      final profile = await _ds.getMyProfile();

      // Auto-create if no row exists (trigger may not have fired).
      if (profile == null) {
        AppLogger.info('No profile row — auto-creating', tag: _tag);
        return await _ds.upsertMyProfile(
          const ProfilePatch(displayName: 'Runner'),
        );
      }
      return profile;
    } catch (e) {
      AppLogger.error('getMyProfile failed: $e', tag: _tag, error: e);
      return null;
    }
  }

  @override
  Future<ProfileEntity> upsertMyProfile(ProfilePatch patch) async {
    try {
      return await _ds.upsertMyProfile(patch);
    } catch (e) {
      AppLogger.error('upsertMyProfile failed: $e', tag: _tag, error: e);
      rethrow;
    }
  }
}
