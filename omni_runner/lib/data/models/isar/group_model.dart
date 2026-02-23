import 'package:isar/isar.dart';

part 'group_model.g.dart';

/// Isar collection for persisting groups.
///
/// Maps to/from [GroupEntity] in the domain layer.
///
/// GroupPrivacy ordinal mapping (append-only — DECISAO 018):
///   0 = open, 1 = closed, 2 = secret
@collection
class GroupRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String groupUuid;

  late String name;
  late String description;
  String? avatarUrl;

  @Index()
  late String createdByUserId;

  late int createdAtMs;

  /// [GroupPrivacy] as integer ordinal.
  late int privacyOrdinal;

  late int maxMembers;
  late int memberCount;
}

/// Isar collection for group membership records.
///
/// Maps to/from [GroupMemberEntity] in the domain layer.
///
/// GroupRole ordinal mapping (append-only — DECISAO 018):
///   0 = admin, 1 = moderator, 2 = member
///
/// GroupMemberStatus ordinal mapping (append-only — DECISAO 018):
///   0 = active, 1 = banned, 2 = left
@collection
class GroupMemberRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String memberUuid;

  @Index()
  late String groupId;

  @Index()
  late String userId;

  late String displayName;

  /// [GroupRole] as integer ordinal.
  late int roleOrdinal;

  /// [GroupMemberStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;

  late int joinedAtMs;
}

/// Isar collection for group goals.
///
/// Maps to/from [GroupGoalEntity] in the domain layer.
///
/// GoalMetric ordinal mapping (append-only — DECISAO 018):
///   0 = distance, 1 = sessions, 2 = movingTime
///
/// GoalStatus ordinal mapping (append-only — DECISAO 018):
///   0 = active, 1 = completed, 2 = expired
@collection
class GroupGoalRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String goalUuid;

  @Index()
  late String groupId;

  late String title;
  late String description;

  late double targetValue;
  late double currentValue;

  /// [GoalMetric] as integer ordinal.
  late int metricOrdinal;

  late int startsAtMs;
  late int endsAtMs;

  late String createdByUserId;

  /// [GoalStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;
}
