import 'package:omni_runner/domain/entities/badge_award_entity.dart';

/// Contract for persisting badge unlocks.
///
/// The combination of [userId] + [badgeId] is unique.
/// Awards are never deleted — a badge cannot be re-locked.
abstract interface class IBadgeAwardRepo {
  Future<void> save(BadgeAwardEntity award);

  /// All badges unlocked by a user, ordered by [unlockedAtMs] descending.
  Future<List<BadgeAwardEntity>> getByUserId(String userId);

  /// Whether the user has already unlocked this specific badge.
  Future<bool> isUnlocked(String userId, String badgeId);
}
