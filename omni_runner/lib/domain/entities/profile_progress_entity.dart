import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// XP source categories for daily cap enforcement.
///
/// Session XP and bonus XP (badges/missions) have independent caps.
/// See `docs/PROGRESSION_SPEC.md` §4.
enum XpSource {
  session,
  badge,
  mission,
  streak,
  challenge,
}

/// Immutable record of a single XP credit.
///
/// Append-only — once created, never mutated or deleted.
/// Mirrors the pattern of [LedgerEntryEntity] for OmniCoins.
final class XpTransactionEntity extends Equatable {
  final String id;
  final String userId;
  final int xp;
  final XpSource source;

  /// Links to the entity that generated this XP.
  /// - [XpSource.session] → session ID
  /// - [XpSource.badge] → badge ID
  /// - [XpSource.mission] → mission ID
  /// - [XpSource.streak] → streak milestone key (e.g. "daily_7")
  /// - [XpSource.challenge] → challenge ID
  final String? refId;

  final int createdAtMs;

  const XpTransactionEntity({
    required this.id,
    required this.userId,
    required this.xp,
    required this.source,
    this.refId,
    required this.createdAtMs,
  });

  @override
  List<Object?> get props => [id, userId, xp, source, refId, createdAtMs];
}

/// A user's aggregated progression state.
///
/// XP is permanent — it never decreases.
/// Level is derived deterministically from [totalXp] via [level].
///
/// Holds denormalized streak counters for fast UI reads.
/// The authoritative streak state lives in the XP transaction log
/// and is reconciled by [UpdateStreak].
///
/// See `docs/PROGRESSION_SPEC.md` §2–§4.
final class ProfileProgressEntity extends Equatable {
  final String userId;

  /// Lifetime accumulated XP. Always ≥ 0, never decreases.
  final int totalXp;

  /// XP earned in the current season (reset each season).
  final int seasonXp;

  /// ID of the current season this [seasonXp] belongs to. Null if no season.
  final String? currentSeasonId;

  /// Current daily streak count (consecutive days with ≥ 1 verified session).
  final int dailyStreakCount;

  /// UTC day (ms epoch of midnight) of the last session that extended the streak.
  final int? lastStreakDayMs;

  /// Best streak ever achieved.
  final int streakBest;

  /// Whether a freeze is available (earned: 1 per 7 streak days).
  final bool hasFreezeAvailable;

  /// Weekly verified session count for the current ISO week.
  final int weeklySessionCount;

  /// Monthly verified session count for the current calendar month.
  final int monthlySessionCount;

  /// Lifetime verified session count.
  final int lifetimeSessionCount;

  /// Lifetime accumulated distance in meters.
  final double lifetimeDistanceM;

  /// Lifetime accumulated moving time in milliseconds.
  final int lifetimeMovingMs;

  const ProfileProgressEntity({
    required this.userId,
    this.totalXp = 0,
    this.seasonXp = 0,
    this.currentSeasonId,
    this.dailyStreakCount = 0,
    this.streakBest = 0,
    this.lastStreakDayMs,
    this.hasFreezeAvailable = false,
    this.weeklySessionCount = 0,
    this.monthlySessionCount = 0,
    this.lifetimeSessionCount = 0,
    this.lifetimeDistanceM = 0.0,
    this.lifetimeMovingMs = 0,
  });

  // ── Derived fields ──

  /// Current level derived from [totalXp].
  ///
  /// `levelFromXp(xp) = floor((xp / 100)^(2/3))`
  /// Clamped to ≥ 0.
  int get level {
    if (totalXp <= 0) return 0;
    return math.max(0, math.pow(totalXp / 100, 2 / 3).floor());
  }

  /// XP required to reach [level].
  static int xpForLevel(int n) {
    if (n <= 0) return 0;
    return (100 * math.pow(n, 1.5)).floor();
  }

  /// XP required to reach the *next* level after [level].
  int get xpForNextLevel => xpForLevel(level + 1);

  /// How much XP the user has earned *within* the current level.
  int get xpInCurrentLevel => totalXp - xpForLevel(level);

  /// How much XP is needed to advance from the current level to the next.
  int get xpToNextLevel => xpForNextLevel - totalXp;

  /// Lifetime distance in kilometers.
  double get lifetimeDistanceKm => lifetimeDistanceM / 1000.0;

  /// Lifetime moving time in minutes.
  double get lifetimeMovingMin => lifetimeMovingMs / 60000.0;

  ProfileProgressEntity copyWith({
    int? totalXp,
    int? seasonXp,
    String? currentSeasonId,
    int? dailyStreakCount,
    int? streakBest,
    int? lastStreakDayMs,
    bool? hasFreezeAvailable,
    int? weeklySessionCount,
    int? monthlySessionCount,
    int? lifetimeSessionCount,
    double? lifetimeDistanceM,
    int? lifetimeMovingMs,
  }) =>
      ProfileProgressEntity(
        userId: userId,
        totalXp: totalXp ?? this.totalXp,
        seasonXp: seasonXp ?? this.seasonXp,
        currentSeasonId: currentSeasonId ?? this.currentSeasonId,
        dailyStreakCount: dailyStreakCount ?? this.dailyStreakCount,
        streakBest: streakBest ?? this.streakBest,
        lastStreakDayMs: lastStreakDayMs ?? this.lastStreakDayMs,
        hasFreezeAvailable: hasFreezeAvailable ?? this.hasFreezeAvailable,
        weeklySessionCount: weeklySessionCount ?? this.weeklySessionCount,
        monthlySessionCount: monthlySessionCount ?? this.monthlySessionCount,
        lifetimeSessionCount:
            lifetimeSessionCount ?? this.lifetimeSessionCount,
        lifetimeDistanceM: lifetimeDistanceM ?? this.lifetimeDistanceM,
        lifetimeMovingMs: lifetimeMovingMs ?? this.lifetimeMovingMs,
      );

  @override
  List<Object?> get props => [
        userId,
        totalXp,
        seasonXp,
        currentSeasonId,
        dailyStreakCount,
        streakBest,
        lastStreakDayMs,
        hasFreezeAvailable,
        weeklySessionCount,
        monthlySessionCount,
        lifetimeSessionCount,
        lifetimeDistanceM,
        lifetimeMovingMs,
      ];
}
