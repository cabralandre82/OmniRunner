// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

part 'ledger_record.g.dart';

/// Isar collection for the append-only Coins ledger.
///
/// Maps to/from [LedgerEntryEntity] in the domain layer.
/// Entries are never updated or deleted.
///
/// LedgerReason ordinal mapping (append-only — never reorder):
///   0 = sessionCompleted, 1 = challengeOneVsOneCompleted,
///   2 = challengeOneVsOneWon, 3 = challengeGroupCompleted,
///   4 = streakWeekly, 5 = streakMonthly,
///   6 = prDistance, 7 = prPace,
///   8 = challengeEntryFee, 9 = challengePoolWon,
///   10 = challengeEntryRefund, 11 = cosmeticPurchase,
///   12 = adminAdjustment, 13 = badgeReward, 14 = missionReward,
///   15 = crossAssessoriaPending, 16 = crossAssessoriaCleared,
///   17 = crossAssessoriaBurned, 18 = challengeTeamCompleted,
///   19 = challengeTeamWon
@collection
class LedgerRecord {
  Id isarId = Isar.autoIncrement;

  /// Application-level unique identifier (UUID v4). Dedup key.
  @Index(unique: true)
  late String entryUuid;

  /// Owner user ID.
  @Index()
  late String userId;

  /// Signed coin amount: positive = credit, negative = debit.
  late int deltaCoins;

  /// LedgerReason as integer ordinal.
  late int reasonOrdinal;

  /// Optional reference ID (session/challenge/item).
  @Index()
  String? refId;

  /// The assessoria (group) that issued/emitted these coins.
  /// Null for legacy entries or system-generated transactions.
  @Index()
  String? issuerGroupId;

  /// When this entry was recorded (ms epoch UTC).
  @Index()
  late int createdAtMs;
}
