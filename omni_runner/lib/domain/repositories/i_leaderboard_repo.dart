import 'package:omni_runner/domain/entities/leaderboard_entity.dart';

/// Contract for fetching leaderboard snapshots.
///
/// The implementation decides the data source (Supabase, Isar cache, etc.).
/// The BLoC only depends on this interface.
abstract interface class ILeaderboardRepo {
  /// Fetches the most recent leaderboard matching the given filters.
  ///
  /// Returns `null` if no leaderboard exists for the given criteria.
  Future<LeaderboardEntity?> fetchLeaderboard({
    required LeaderboardScope scope,
    required LeaderboardPeriod period,
    required LeaderboardMetric metric,
    String? groupId,
    String? championshipId,
  });
}
