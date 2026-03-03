import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';

sealed class AthleteProfileState extends Equatable {
  const AthleteProfileState();

  @override
  List<Object?> get props => [];
}

final class AthleteProfileInitial extends AthleteProfileState {
  const AthleteProfileInitial();
}

final class AthleteProfileLoading extends AthleteProfileState {
  const AthleteProfileLoading();
}

final class AthleteProfileLoaded extends AthleteProfileState {
  final List<CoachingTagEntity> tags;
  final List<CoachingTagEntity> allGroupTags;
  final List<AthleteNoteEntity> notes;
  final MemberStatusEntity? status;
  final String athleteUserId;
  final String groupId;

  const AthleteProfileLoaded({
    required this.tags,
    required this.allGroupTags,
    required this.notes,
    this.status,
    required this.athleteUserId,
    required this.groupId,
  });

  @override
  List<Object?> get props => [
        tags,
        allGroupTags,
        notes,
        status,
        athleteUserId,
        groupId,
      ];
}

final class AthleteProfileError extends AthleteProfileState {
  final String message;

  const AthleteProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
