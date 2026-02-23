import 'package:equatable/equatable.dart';

/// How hard the mission is — determines reward range and typical deadline.
///
/// See `docs/PROGRESSION_SPEC.md` §7.4.
enum MissionDifficulty {
  /// 30–50 XP, 5–10 Coins, ~24h deadline.
  easy,

  /// 80–150 XP, 15–30 Coins, ~7 day deadline.
  medium,

  /// 200–400 XP, 50–100 Coins, ~90 day deadline (season).
  hard,
}

/// Slot type that controls when the mission rotates.
enum MissionSlot {
  /// Renewed every 24h UTC midnight. Slots 1–2.
  daily,

  /// Renewed every Monday 00:00 UTC. Slots 3–4.
  weekly,

  /// Fixed for the season duration. Slot 5.
  season,
}

// ── Mission Criteria (sealed) ───────────────────────────────

/// Condition that must be met to complete a mission.
///
/// Sealed for exhaustive pattern-matching in the progress checker.
/// All values use domain canonical units (meters, sec/km, ms).
sealed class MissionCriteria extends Equatable {
  const MissionCriteria();
}

/// Accumulate ≥ [targetM] meters across verified sessions within the deadline.
final class AccumulateDistance extends MissionCriteria {
  final double targetM;
  const AccumulateDistance(this.targetM);

  @override
  List<Object?> get props => [targetM];
}

/// Complete ≥ [targetCount] verified sessions within the deadline.
final class CompleteSessionCount extends MissionCriteria {
  final int targetCount;
  const CompleteSessionCount(this.targetCount);

  @override
  List<Object?> get props => [targetCount];
}

/// Achieve average pace < [maxPaceSecPerKm] in a single session ≥ [minDistanceM].
final class AchievePaceTarget extends MissionCriteria {
  final double maxPaceSecPerKm;
  final double minDistanceM;
  const AchievePaceTarget({
    required this.maxPaceSecPerKm,
    this.minDistanceM = 5000.0,
  });

  @override
  List<Object?> get props => [maxPaceSecPerKm, minDistanceM];
}

/// Complete a single session ≥ [targetMs] milliseconds of moving time.
final class SingleSessionDurationTarget extends MissionCriteria {
  final int targetMs;
  const SingleSessionDurationTarget(this.targetMs);

  @override
  List<Object?> get props => [targetMs];
}

/// Spend ≥ [targetMs] milliseconds in HR zone [zoneIndex] within a single session.
final class HrZoneTime extends MissionCriteria {
  /// 1-indexed HR zone (1 = recovery, 5 = max effort).
  final int zoneIndex;
  final int targetMs;
  const HrZoneTime({required this.zoneIndex, required this.targetMs});

  @override
  List<Object?> get props => [zoneIndex, targetMs];
}

/// Maintain a daily streak of ≥ [days] consecutive days.
final class MaintainStreak extends MissionCriteria {
  final int days;
  const MaintainStreak(this.days);

  @override
  List<Object?> get props => [days];
}

/// Complete ≥ [count] challenges within the deadline.
final class CompleteChallenges extends MissionCriteria {
  final int count;
  const CompleteChallenges(this.count);

  @override
  List<Object?> get props => [count];
}

// ── Mission Definition ──────────────────────────────────────

/// Template that defines what a mission requires and what it rewards.
///
/// Missions rotate on a schedule: daily (24h), weekly (Monday),
/// or per-season (90 days). The generator creates instances from
/// these definitions and assigns them to user slots.
///
/// Immutable value object — no behavior.
/// See `docs/PROGRESSION_SPEC.md` §7.
final class MissionEntity extends Equatable {
  final String id;

  /// Display title (PT-BR).
  final String title;

  /// Clear description of the objective.
  final String description;

  final MissionDifficulty difficulty;
  final MissionSlot slot;

  /// XP awarded on completion.
  final int xpReward;

  /// OmniCoins awarded on completion.
  final int coinsReward;

  /// Condition that must be met.
  final MissionCriteria criteria;

  /// Deadline (ms since epoch, UTC). Null = no expiration.
  final int? expiresAtMs;

  /// If non-null, this mission belongs to a specific season.
  final String? seasonId;

  /// How many times a single user can complete this mission.
  /// 1 = one-time (default); >1 = repeatable.
  final int maxCompletions;

  /// Minimum ms between successive completions (for repeatables).
  /// Null = no cooldown.
  final int? cooldownMs;

  const MissionEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.slot,
    required this.xpReward,
    this.coinsReward = 0,
    required this.criteria,
    this.expiresAtMs,
    this.seasonId,
    this.maxCompletions = 1,
    this.cooldownMs,
  });

  /// Whether this mission can still be completed given [nowMs].
  bool isExpired(int nowMs) =>
      expiresAtMs != null && nowMs > expiresAtMs!;

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        difficulty,
        slot,
        xpReward,
        coinsReward,
        criteria,
        expiresAtMs,
        seasonId,
        maxCompletions,
        cooldownMs,
      ];
}
