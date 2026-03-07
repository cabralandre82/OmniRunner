// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'progress_model.g.dart';

/// Isar collection for user progression state.
///
/// One record per user. Maps to/from [ProfileProgressEntity].
@collection
class ProfileProgressRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String userId;

  late int totalXp;
  late int seasonXp;
  String? currentSeasonId;

  late int dailyStreakCount;
  late int streakBest;
  int? lastStreakDayMs;
  late bool hasFreezeAvailable;

  late int weeklySessionCount;
  late int monthlySessionCount;
  late int lifetimeSessionCount;
  late double lifetimeDistanceM;
  late int lifetimeMovingMs;
}

/// Isar collection for the append-only XP transaction log.
///
/// Maps to/from [XpTransactionEntity]. Never updated or deleted.
///
/// XpSource ordinal mapping:
///   0 = session, 1 = badge, 2 = mission, 3 = streak, 4 = challenge
@collection
class XpTransactionRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String txUuid;

  @Index()
  late String userId;

  late int xp;

  /// [XpSource] as integer ordinal.
  late int sourceOrdinal;

  @Index()
  String? refId;

  @Index()
  late int createdAtMs;
}
