import 'package:isar/isar.dart';

part 'coaching_member_model.g.dart';

/// Isar collection for persisting coaching group members.
///
/// Maps to/from [CoachingMemberEntity] in the domain layer.
///
/// CoachingRole ordinal mapping (append-only — DECISAO 018):
///   0 = adminMaster (was coach), 1 = assistente (was assistant),
///   2 = atleta (was athlete), 3 = professor (new)
@collection
class CoachingMemberRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String memberUuid;

  @Index(unique: true, composite: [CompositeIndex('userId')], name: 'groupId_userId')
  @Index()
  late String groupId;

  @Index()
  late String userId;

  late String displayName;

  /// [CoachingRole] as integer ordinal.
  late int roleOrdinal;

  late int joinedAtMs;
}
