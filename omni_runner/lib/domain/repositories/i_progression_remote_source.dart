import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';

/// Remote data source for progression data (profile, XP, weekly goals, badges).
///
/// The BLoC calls this to sync server state, then reads from local repos.
abstract interface class IProgressionRemoteSource {
  /// Triggers server-side recalculation and badge evaluation for [userId].
  /// No-op when offline.
  Future<void> recalculateAndEvaluate(String userId);

  /// Fetches the profile progress snapshot for [userId].
  Future<ProfileProgressEntity?> fetchProfileProgress(String userId);

  /// Fetches recent XP transactions for [userId].
  Future<List<XpTransactionEntity>> fetchXpTransactions(String userId);

  /// Fetches (or generates) the current weekly goal for [userId].
  Future<WeeklyGoalEntity?> fetchWeeklyGoal(String userId);

  /// Fetches badge catalog and earned badge IDs for [userId].
  Future<({List<Map<String, dynamic>> catalog, Set<String> earnedIds})>
      fetchBadges(String userId);
}
