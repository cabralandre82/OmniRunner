import 'package:equatable/equatable.dart';

final class AthleteNoteEntity extends Equatable {
  final String id;
  final String groupId;
  final String athleteUserId;
  final String createdBy;
  final String note;
  final DateTime createdAt;

  /// Display name of the note author, populated from joins.
  final String? authorDisplayName;

  const AthleteNoteEntity({
    required this.id,
    required this.groupId,
    required this.athleteUserId,
    required this.createdBy,
    required this.note,
    required this.createdAt,
    this.authorDisplayName,
  });

  @override
  List<Object?> get props => [
        id, groupId, athleteUserId, createdBy, note, createdAt,
      ];
}
