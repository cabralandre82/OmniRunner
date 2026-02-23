import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';

/// Stub implementation for offline / mock mode.
///
/// Always succeeds after a brief delay, returning the requested group ID.
final class StubSwitchAssessoriaRepo implements ISwitchAssessoriaRepo {
  const StubSwitchAssessoriaRepo();

  @override
  Future<String> switchTo(String newGroupId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return newGroupId;
  }
}
