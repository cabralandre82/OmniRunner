import 'package:equatable/equatable.dart';

sealed class AnnouncementFeedEvent extends Equatable {
  const AnnouncementFeedEvent();

  @override
  List<Object?> get props => [];
}

final class LoadAnnouncements extends AnnouncementFeedEvent {
  final String groupId;
  const LoadAnnouncements(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

final class RefreshAnnouncements extends AnnouncementFeedEvent {
  const RefreshAnnouncements();
}

final class MarkAsRead extends AnnouncementFeedEvent {
  final String announcementId;
  const MarkAsRead(this.announcementId);

  @override
  List<Object?> get props => [announcementId];
}
