import 'package:equatable/equatable.dart';

/// Record of a badge unlocked by a specific user.
///
/// Immutable — once created, never mutated. A badge cannot be re-locked.
/// The combination of [userId] + [badgeId] is unique (enforced by repo).
///
/// See `docs/PROGRESSION_SPEC.md` §5.2 / §5.4.
final class BadgeAwardEntity extends Equatable {
  /// Unique record ID (UUID v4).
  final String id;

  final String userId;

  /// References [BadgeEntity.id] from the catalog.
  final String badgeId;

  /// Session that triggered the unlock. Null for non-session badges
  /// (e.g. social badges triggered by challenge completion).
  final String? triggerSessionId;

  /// When the badge was unlocked (ms since epoch, UTC).
  final int unlockedAtMs;

  /// XP that was credited for this unlock.
  final int xpAwarded;

  /// OmniCoins that were credited for this unlock.
  final int coinsAwarded;

  const BadgeAwardEntity({
    required this.id,
    required this.userId,
    required this.badgeId,
    this.triggerSessionId,
    required this.unlockedAtMs,
    this.xpAwarded = 0,
    this.coinsAwarded = 0,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        badgeId,
        triggerSessionId,
        unlockedAtMs,
        xpAwarded,
        coinsAwarded,
      ];
}
