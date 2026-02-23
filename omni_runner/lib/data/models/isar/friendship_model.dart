import 'package:isar/isar.dart';

part 'friendship_model.g.dart';

/// Isar collection for persisting friendships.
///
/// Maps to/from [FriendshipEntity] in the domain layer.
///
/// FriendshipStatus ordinal mapping (append-only — DECISAO 018):
///   0 = pending, 1 = accepted, 2 = declined, 3 = blocked
@collection
class FriendshipRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String friendshipUuid;

  /// User who sent the request.
  @Index(unique: true, composite: [CompositeIndex('userIdB')])
  late String userIdA;

  /// User who received the request.
  @Index()
  late String userIdB;

  /// [FriendshipStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;

  late int createdAtMs;

  /// Null if not yet accepted.
  int? acceptedAtMs;
}
