import 'package:omni_runner/core/errors/coaching_failures.dart';

/// Contract for switching the user's active coaching group (assessoria).
///
/// The server-side RPC (`fn_switch_assessoria`) burns remaining coins,
/// updates `profiles.active_coaching_group_id`, and manages membership.
///
/// Throws [SwitchAssessoriaFailed] on error.
abstract interface class ISwitchAssessoriaRepo {
  /// Switches the authenticated user to [newGroupId].
  ///
  /// Returns the new group ID on success.
  /// Throws [SwitchAssessoriaFailed] on failure.
  Future<String> switchTo(String newGroupId);
}
