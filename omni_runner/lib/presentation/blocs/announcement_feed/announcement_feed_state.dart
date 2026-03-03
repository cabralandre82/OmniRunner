import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';

sealed class AnnouncementFeedState extends Equatable {
  const AnnouncementFeedState();

  @override
  List<Object?> get props => [];
}

final class AnnouncementFeedInitial extends AnnouncementFeedState {
  const AnnouncementFeedInitial();
}

final class AnnouncementFeedLoading extends AnnouncementFeedState {
  const AnnouncementFeedLoading();
}

final class AnnouncementFeedLoaded extends AnnouncementFeedState {
  final List<AnnouncementEntity> announcements;
  final int unreadCount;

  const AnnouncementFeedLoaded({
    required this.announcements,
    required this.unreadCount,
  });

  @override
  List<Object?> get props => [announcements, unreadCount];
}

final class AnnouncementFeedError extends AnnouncementFeedState {
  final String message;
  const AnnouncementFeedError(this.message);

  @override
  List<Object?> get props => [message];
}
