import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/race_event_entity.dart';

/// Final result of an athlete in a coaching race event.
///
/// Computed when the race is settled (status → [RaceEventStatus.completed]).
/// Immutable — once computed, results are never updated.
///
/// One result per (raceEventId, userId) — enforced by the repo.
///
/// Immutable value object. See Phase 16 — Event Gamification Engine.
final class RaceResultEntity extends Equatable {
  /// Unique identifier (UUID v4).
  final String id;

  final String raceEventId;
  final String userId;

  /// Cached for offline display.
  final String displayName;

  /// Final ranking position (dense ranking with skips, 1-indexed).
  final int finalRank;

  /// Total distance accumulated during the event window (meters).
  final double totalDistanceM;

  /// Total moving time accumulated during the event window (ms).
  final int totalMovingMs;

  /// Best average pace among contributing sessions (sec/km).
  /// Null if no session with pace data contributed.
  final double? bestPaceSecPerKm;

  /// Number of verified sessions that contributed to this result.
  final int sessionCount;

  /// Whether the athlete reached the race's target distance.
  final bool targetCompleted;

  /// XP awarded for this result.
  final int xpAwarded;

  /// Coins awarded for this result.
  final int coinsAwarded;

  /// Badge ID unlocked by this result. Null if none.
  final String? badgeId;

  /// When this result was computed (ms since epoch, UTC).
  final int computedAtMs;

  const RaceResultEntity({
    required this.id,
    required this.raceEventId,
    required this.userId,
    required this.displayName,
    required this.finalRank,
    this.totalDistanceM = 0.0,
    this.totalMovingMs = 0,
    this.bestPaceSecPerKm,
    this.sessionCount = 0,
    this.targetCompleted = false,
    this.xpAwarded = 0,
    this.coinsAwarded = 0,
    this.badgeId,
    required this.computedAtMs,
  });

  /// Formatted pace string (e.g. "5:30/km"). Returns "—" if unavailable.
  String get formattedPace {
    final pace = bestPaceSecPerKm;
    if (pace == null || pace == double.infinity || pace <= 0) return '—';
    final min = pace ~/ 60;
    final sec = (pace % 60).toInt();
    return '$min:${sec.toString().padLeft(2, '0')}/km';
  }

  /// Whether this athlete finished on the podium (top 3).
  bool get isPodium => finalRank <= 3;

  @override
  List<Object?> get props => [
        id,
        raceEventId,
        userId,
        displayName,
        finalRank,
        totalDistanceM,
        totalMovingMs,
        bestPaceSecPerKm,
        sessionCount,
        targetCompleted,
        xpAwarded,
        coinsAwarded,
        badgeId,
        computedAtMs,
      ];
}
