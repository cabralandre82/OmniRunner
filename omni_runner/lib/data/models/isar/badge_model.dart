import 'package:isar/isar.dart';

part 'badge_model.g.dart';

/// Isar collection for badge unlocks.
///
/// Maps to/from [BadgeAwardEntity]. Never updated or deleted.
/// The combination (userId, badgeId) is unique.
@collection
class BadgeAwardRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String awardUuid;

  @Index()
  late String userId;

  @Index()
  late String badgeId;

  String? triggerSessionId;

  late int unlockedAtMs;
  late int xpAwarded;
  late int coinsAwarded;
}
