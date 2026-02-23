import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';

/// Executes an assessoria switch for the authenticated user.
///
/// Delegates to [ISwitchAssessoriaRepo] which calls the server RPC
/// `fn_switch_assessoria`. On the server: remaining coins are burned,
/// `profiles.active_coaching_group_id` is updated, and membership changes.
///
/// The caller (BLoC) must show a confirmation dialog BEFORE calling this,
/// warning the user that unspent tokens will be invalidated.
///
/// Throws [SwitchAssessoriaFailed] on error.
final class SwitchAssessoria {
  final ISwitchAssessoriaRepo _repo;

  const SwitchAssessoria({required ISwitchAssessoriaRepo repo}) : _repo = repo;

  Future<String> call(String newGroupId) => _repo.switchTo(newGroupId);
}
