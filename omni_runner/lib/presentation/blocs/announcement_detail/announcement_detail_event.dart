import 'package:equatable/equatable.dart';

sealed class AnnouncementDetailEvent extends Equatable {
  const AnnouncementDetailEvent();

  @override
  List<Object?> get props => [];
}

final class LoadAnnouncementDetail extends AnnouncementDetailEvent {
  final String announcementId;
  const LoadAnnouncementDetail(this.announcementId);

  @override
  List<Object?> get props => [announcementId];
}

final class TogglePin extends AnnouncementDetailEvent {
  const TogglePin();
}

final class UpdateAnnouncement extends AnnouncementDetailEvent {
  final String title;
  final String body;
  const UpdateAnnouncement({required this.title, required this.body});

  @override
  List<Object?> get props => [title, body];
}

final class DeleteAnnouncement extends AnnouncementDetailEvent {
  const DeleteAnnouncement();
}

final class ConfirmRead extends AnnouncementDetailEvent {
  const ConfirmRead();
}
