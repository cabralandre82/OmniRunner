import 'package:omni_runner/domain/entities/profile_progress_entity.dart';

/// Contract for persisting and retrieving user progression state.
///
/// Creates a default zero-state profile if none exists.
abstract interface class IProfileProgressRepo {
  Future<ProfileProgressEntity> getByUserId(String userId);

  Future<void> save(ProfileProgressEntity profile);
}
