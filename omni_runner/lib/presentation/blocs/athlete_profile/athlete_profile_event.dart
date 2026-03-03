import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';

sealed class AthleteProfileEvent extends Equatable {
  const AthleteProfileEvent();

  @override
  List<Object?> get props => [];
}

final class LoadAthleteProfile extends AthleteProfileEvent {
  final String groupId;
  final String athleteUserId;

  const LoadAthleteProfile({
    required this.groupId,
    required this.athleteUserId,
  });

  @override
  List<Object?> get props => [groupId, athleteUserId];
}

final class RefreshAthleteProfile extends AthleteProfileEvent {
  const RefreshAthleteProfile();
}

final class AddNote extends AthleteProfileEvent {
  final String note;

  const AddNote(this.note);

  @override
  List<Object?> get props => [note];
}

final class DeleteNote extends AthleteProfileEvent {
  final String noteId;

  const DeleteNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

final class AssignTag extends AthleteProfileEvent {
  final String tagId;

  const AssignTag(this.tagId);

  @override
  List<Object?> get props => [tagId];
}

final class RemoveTag extends AthleteProfileEvent {
  final String tagId;

  const RemoveTag(this.tagId);

  @override
  List<Object?> get props => [tagId];
}

final class UpdateStatus extends AthleteProfileEvent {
  final MemberStatusValue status;

  const UpdateStatus(this.status);

  @override
  List<Object?> get props => [status];
}
