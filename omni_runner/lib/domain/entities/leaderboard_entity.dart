import 'package:equatable/equatable.dart';

/// Scope that determines which users are eligible for a leaderboard.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum LeaderboardScope {
  /// All opt-in users.
  global,

  /// Only accepted friends of the requesting user.
  friends,

  /// Members of a specific group.
  group,

  /// All opt-in users within the current season.
  season,

  /// Members of a coaching group (assessoria).
  assessoria,

  /// Participants of a championship with active badge.
  championship,
}

/// Time period that a leaderboard covers.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum LeaderboardPeriod {
  /// Monday 00:00 UTC → Sunday 23:59 UTC.
  weekly,

  /// 1st of month 00:00 UTC → last day 23:59 UTC.
  monthly,

  /// Full season (90 days).
  season,
}

/// Metric used to rank users in a leaderboard.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum LeaderboardMetric {
  /// Total verified distance in meters.
  distance,

  /// Number of verified sessions.
  sessions,

  /// Total moving time in milliseconds.
  movingTime,

  /// Average pace in sec/km (lower is better).
  avgPace,

  /// Season XP from [ProfileProgressEntity.seasonXp].
  seasonXp,

  /// Composite score: floor(dist_km) + (challenge_wins × 5).
  composite,
}

/// A frozen snapshot of a leaderboard for a specific scope, period, and metric.
///
/// Materialized after each period closes or on-demand with caching.
/// Once a period ends, the snapshot is immutable.
///
/// See `docs/SOCIAL_SPEC.md` §4.
final class LeaderboardEntity extends Equatable {
  /// Unique identifier for this snapshot (scope + metric + periodKey).
  final String id;

  final LeaderboardScope scope;

  /// For [LeaderboardScope.group], the group ID. Null otherwise.
  final String? groupId;

  final LeaderboardPeriod period;
  final LeaderboardMetric metric;

  /// Human-readable period key, e.g. "2026-W08" or "2026-02".
  final String periodKey;

  /// Ordered list of entries (rank 1 first).
  final List<LeaderboardEntryEntity> entries;

  /// When this snapshot was computed (ms since epoch, UTC).
  final int computedAtMs;

  /// Whether this is the final (immutable) snapshot for a closed period.
  final bool isFinal;

  const LeaderboardEntity({
    required this.id,
    required this.scope,
    this.groupId,
    required this.period,
    required this.metric,
    required this.periodKey,
    this.entries = const [],
    required this.computedAtMs,
    this.isFinal = false,
  });

  @override
  List<Object?> get props => [
        id,
        scope,
        groupId,
        period,
        metric,
        periodKey,
        entries,
        computedAtMs,
        isFinal,
      ];
}

/// A single row in a leaderboard.
///
/// Immutable value object. No logic.
/// See `docs/SOCIAL_SPEC.md` §4.1.
final class LeaderboardEntryEntity extends Equatable {
  final String userId;

  /// Cached for offline rendering.
  final String displayName;

  /// Avatar URL. Null if not set.
  final String? avatarUrl;

  /// User level (derived from XP, cached for display).
  final int level;

  /// Metric value (meters, count, ms, sec/km, or XP depending on metric).
  final double value;

  /// 1-indexed position. Ties share the same rank; next rank skips.
  final int rank;

  /// Period key this entry belongs to (e.g. "2026-W08").
  final String periodKey;

  const LeaderboardEntryEntity({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.level,
    required this.value,
    required this.rank,
    required this.periodKey,
  });

  @override
  List<Object?> get props => [
        userId,
        displayName,
        avatarUrl,
        level,
        value,
        rank,
        periodKey,
      ];
}
