import 'package:isar/isar.dart';

part 'coaching_invite_model.g.dart';

/// Isar collection for persisting coaching group invitations.
///
/// Maps to/from [CoachingInviteEntity] in the domain layer.
///
/// CoachingInviteStatus ordinal mapping (append-only — DECISAO 018):
///   0 = pending, 1 = accepted, 2 = declined, 3 = expired
@collection
class CoachingInviteRecord {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  late String inviteUuid;

  @Index()
  late String groupId;

  @Index()
  late String invitedUserId;

  late String invitedByUserId;

  /// [CoachingInviteStatus] as integer ordinal.
  @Index()
  late int statusOrdinal;

  late int expiresAtMs;
  late int createdAtMs;
}
