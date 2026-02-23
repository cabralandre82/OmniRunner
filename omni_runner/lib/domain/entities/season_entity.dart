import 'package:equatable/equatable.dart';

/// Lifecycle status of a season.
enum SeasonStatus {
  /// Scheduled but not yet started.
  upcoming,

  /// Currently active — XP earned counts toward season ranking.
  active,

  /// Time window elapsed; rewards being calculated.
  settling,

  /// Settled — rewards distributed, rankings frozen.
  completed,
}

/// Tier in the seasonal ranking, determined by absolute Season XP thresholds.
///
/// See `docs/PROGRESSION_SPEC.md` §8.4.
enum SeasonTier {
  /// 0–999 Season XP.
  bronze,

  /// 1 000–4 999 Season XP.
  silver,

  /// 5 000–14 999 Season XP.
  gold,

  /// 15 000–29 999 Season XP.
  diamond,

  /// 30 000+ Season XP.
  elite,
}

// ── Season Definition ───────────────────────────────────────

/// Metadata for a 90-day season cycle.
///
/// Seasons are trimestral (Jan/Apr/Jul/Oct). The `startsAtMs` and
/// `endsAtMs` define the UTC window. XP earned within this window
/// counts for both lifetime progression and the season ranking.
///
/// Immutable value object.
/// See `docs/PROGRESSION_SPEC.md` §8.
final class SeasonEntity extends Equatable {
  final String id;

  /// Thematic display name (e.g. "Temporada do Inverno 2026").
  final String name;

  final SeasonStatus status;

  /// UTC start (ms epoch). Typically 1st day of quarter, 00:00:00.
  final int startsAtMs;

  /// UTC end (ms epoch). Typically last day of quarter, 23:59:59.
  final int endsAtMs;

  /// Season Pass milestones (sorted ascending Season XP thresholds).
  /// Default: [200, 500, 1000, 2000, 3500, 5000, 7500, 10000, 15000, 20000].
  final List<int> passXpMilestones;

  const SeasonEntity({
    required this.id,
    required this.name,
    required this.status,
    required this.startsAtMs,
    required this.endsAtMs,
    this.passXpMilestones = defaultPassMilestones,
  });

  static const List<int> defaultPassMilestones = [
    200,
    500,
    1000,
    2000,
    3500,
    5000,
    7500,
    10000,
    15000,
    20000,
  ];

  /// Whether the given timestamp falls within this season's window.
  bool containsTimestamp(int ms) => ms >= startsAtMs && ms <= endsAtMs;

  /// Duration in milliseconds.
  int get durationMs => endsAtMs - startsAtMs;

  SeasonEntity copyWith({
    SeasonStatus? status,
  }) =>
      SeasonEntity(
        id: id,
        name: name,
        status: status ?? this.status,
        startsAtMs: startsAtMs,
        endsAtMs: endsAtMs,
        passXpMilestones: passXpMilestones,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        status,
        startsAtMs,
        endsAtMs,
        passXpMilestones,
      ];
}

// ── Season Progress (per user) ──────────────────────────────

/// A user's progress within a specific season.
///
/// [seasonXp] determines the [tier] and which [passXpMilestones]
/// have been claimed. Tier is derived, not stored — computed from
/// [seasonXp] via [tier].
///
/// Immutable value object.
/// See `docs/PROGRESSION_SPEC.md` §8.3–§8.6.
final class SeasonProgressEntity extends Equatable {
  final String userId;
  final String seasonId;

  /// XP earned during this season. Subset of lifetime totalXp.
  final int seasonXp;

  /// Indices (0-based) of pass milestones already claimed.
  /// Used to avoid double-rewarding.
  final List<int> claimedMilestoneIndices;

  /// End-of-season rewards already distributed.
  final bool endRewardsClaimed;

  const SeasonProgressEntity({
    required this.userId,
    required this.seasonId,
    this.seasonXp = 0,
    this.claimedMilestoneIndices = const [],
    this.endRewardsClaimed = false,
  });

  /// Current tier derived from [seasonXp].
  SeasonTier get tier {
    if (seasonXp >= 30000) return SeasonTier.elite;
    if (seasonXp >= 15000) return SeasonTier.diamond;
    if (seasonXp >= 5000) return SeasonTier.gold;
    if (seasonXp >= 1000) return SeasonTier.silver;
    return SeasonTier.bronze;
  }

  /// XP needed to reach the next tier. 0 if already elite.
  int get xpToNextTier => switch (tier) {
        SeasonTier.bronze => 1000 - seasonXp,
        SeasonTier.silver => 5000 - seasonXp,
        SeasonTier.gold => 15000 - seasonXp,
        SeasonTier.diamond => 30000 - seasonXp,
        SeasonTier.elite => 0,
      };

  /// Number of pass milestones unlocked (not necessarily claimed).
  int unlockedMilestones(List<int> passXpMilestones) {
    var count = 0;
    for (final threshold in passXpMilestones) {
      if (seasonXp >= threshold) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// Indices of milestones unlocked but not yet claimed.
  List<int> unclaimedMilestones(List<int> passXpMilestones) {
    final result = <int>[];
    for (var i = 0; i < passXpMilestones.length; i++) {
      if (seasonXp >= passXpMilestones[i] &&
          !claimedMilestoneIndices.contains(i)) {
        result.add(i);
      }
    }
    return result;
  }

  SeasonProgressEntity copyWith({
    int? seasonXp,
    List<int>? claimedMilestoneIndices,
    bool? endRewardsClaimed,
  }) =>
      SeasonProgressEntity(
        userId: userId,
        seasonId: seasonId,
        seasonXp: seasonXp ?? this.seasonXp,
        claimedMilestoneIndices:
            claimedMilestoneIndices ?? this.claimedMilestoneIndices,
        endRewardsClaimed: endRewardsClaimed ?? this.endRewardsClaimed,
      );

  @override
  List<Object?> get props => [
        userId,
        seasonId,
        seasonXp,
        claimedMilestoneIndices,
        endRewardsClaimed,
      ];
}
