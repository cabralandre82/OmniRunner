import 'package:equatable/equatable.dart';

/// Visual category used for grouping and filtering in the UI.
enum BadgeCategory {
  distance,
  frequency,
  speed,
  endurance,
  social,
  special,
}

/// Rarity tier — determines XP reward and visual treatment.
///
/// XP per tier (PROGRESSION_SPEC §5.1):
///   bronze = 50, silver = 100, gold = 200, diamond = 500.
enum BadgeTier {
  bronze,
  silver,
  gold,
  diamond,
}

// ── Badge Criteria (sealed) ─────────────────────────────────

/// Condition that must be met to unlock a badge.
///
/// Sealed so that the evaluator can exhaustively pattern-match.
/// All thresholds use the domain's canonical units
/// (meters, seconds/km, milliseconds).
sealed class BadgeCriteria extends Equatable {
  const BadgeCriteria();
}

/// Single session distance ≥ [thresholdM] meters.
final class SingleSessionDistance extends BadgeCriteria {
  final double thresholdM;
  const SingleSessionDistance(this.thresholdM);

  @override
  List<Object?> get props => [thresholdM];
}

/// Lifetime accumulated distance ≥ [thresholdM] meters.
final class LifetimeDistance extends BadgeCriteria {
  final double thresholdM;
  const LifetimeDistance(this.thresholdM);

  @override
  List<Object?> get props => [thresholdM];
}

/// Lifetime verified session count ≥ [count].
final class SessionCount extends BadgeCriteria {
  final int count;
  const SessionCount(this.count);

  @override
  List<Object?> get props => [count];
}

/// Session average pace < [maxPaceSecPerKm] in a session ≥ [minDistanceM].
final class PaceBelow extends BadgeCriteria {
  final double maxPaceSecPerKm;
  final double minDistanceM;
  const PaceBelow({required this.maxPaceSecPerKm, this.minDistanceM = 5000.0});

  @override
  List<Object?> get props => [maxPaceSecPerKm, minDistanceM];
}

/// Any new personal record for pace (session ≥ [minDistanceM]).
final class PersonalRecordPace extends BadgeCriteria {
  final double minDistanceM;
  const PersonalRecordPace({this.minDistanceM = 1000.0});

  @override
  List<Object?> get props => [minDistanceM];
}

/// Single session duration ≥ [thresholdMs] milliseconds.
final class SingleSessionDuration extends BadgeCriteria {
  final int thresholdMs;
  const SingleSessionDuration(this.thresholdMs);

  @override
  List<Object?> get props => [thresholdMs];
}

/// Lifetime accumulated moving time ≥ [thresholdMs] milliseconds.
final class LifetimeDuration extends BadgeCriteria {
  final int thresholdMs;
  const LifetimeDuration(this.thresholdMs);

  @override
  List<Object?> get props => [thresholdMs];
}

/// Daily streak ≥ [days] consecutive days.
final class DailyStreak extends BadgeCriteria {
  final int days;
  const DailyStreak(this.days);

  @override
  List<Object?> get props => [days];
}

/// Completed challenges count ≥ [count].
final class ChallengesCompleted extends BadgeCriteria {
  final int count;
  const ChallengesCompleted(this.count);

  @override
  List<Object?> get props => [count];
}

/// Won [count] consecutive 1v1 challenges.
final class ConsecutiveWins extends BadgeCriteria {
  final int count;
  const ConsecutiveWins(this.count);

  @override
  List<Object?> get props => [count];
}

/// Rank #1 in a group challenge with ≥ [minParticipants] participants.
final class GroupLeader extends BadgeCriteria {
  final int minParticipants;
  const GroupLeader(this.minParticipants);

  @override
  List<Object?> get props => [minParticipants];
}

/// Session started before [hourUtc] (local time, 24h format).
final class SessionBeforeHour extends BadgeCriteria {
  final int hourLocal;
  const SessionBeforeHour(this.hourLocal);

  @override
  List<Object?> get props => [hourLocal];
}

/// Session started after [hourLocal] (local time, 24h format).
final class SessionAfterHour extends BadgeCriteria {
  final int hourLocal;
  const SessionAfterHour(this.hourLocal);

  @override
  List<Object?> get props => [hourLocal];
}

// ── Badge Definition ────────────────────────────────────────

/// Static definition of a badge from the catalog.
///
/// Immutable value object. The catalog is defined at compile-time
/// and never changes at runtime. The evaluator checks each
/// definition's [criteria] against the user's profile and session.
///
/// See `docs/PROGRESSION_SPEC.md` §5.
final class BadgeEntity extends Equatable {
  /// Stable identifier (e.g. `badge_first_5k`). Never changes.
  final String id;

  final BadgeCategory category;
  final BadgeTier tier;

  /// Display name (PT-BR).
  final String name;

  /// Short description of the unlock condition.
  final String description;

  /// Asset path for the badge icon.
  final String iconAsset;

  /// XP awarded on unlock (50/100/200/500 by tier).
  final int xpReward;

  /// OmniCoins awarded on unlock (0 for most badges).
  final int coinsReward;

  /// Rule that determines when this badge is unlocked.
  final BadgeCriteria criteria;

  /// If true, name and description are hidden until unlocked.
  final bool isSecret;

  /// Optional season ID — makes this badge exclusive to that season.
  final String? seasonId;

  const BadgeEntity({
    required this.id,
    required this.category,
    required this.tier,
    required this.name,
    required this.description,
    this.iconAsset = '',
    required this.xpReward,
    this.coinsReward = 0,
    required this.criteria,
    this.isSecret = false,
    this.seasonId,
  });

  /// Default XP for a given tier.
  static int xpForTier(BadgeTier tier) => switch (tier) {
        BadgeTier.bronze => 50,
        BadgeTier.silver => 100,
        BadgeTier.gold => 200,
        BadgeTier.diamond => 500,
      };

  @override
  List<Object?> get props => [
        id,
        category,
        tier,
        name,
        description,
        iconAsset,
        xpReward,
        coinsReward,
        criteria,
        isSecret,
        seasonId,
      ];
}
