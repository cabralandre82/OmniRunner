import 'package:isar/isar.dart';

part 'coaching_group_model.g.dart';

/// Isar collection for persisting coaching groups.
///
/// Maps to/from [CoachingGroupEntity] in the domain layer.
@collection
class CoachingGroupRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String groupUuid;

  late String name;

  String? logoUrl;

  @Index()
  late String coachUserId;

  late String description;
  late String city;

  @Index(unique: true)
  String? inviteCode;

  late bool inviteEnabled;

  late int createdAtMs;
}
