import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';

sealed class AnnouncementDetailState extends Equatable {
  const AnnouncementDetailState();

  @override
  List<Object?> get props => [];
}

final class AnnouncementDetailInitial extends AnnouncementDetailState {
  const AnnouncementDetailInitial();
}

final class AnnouncementDetailLoading extends AnnouncementDetailState {
  const AnnouncementDetailLoading();
}

final class AnnouncementDetailLoaded extends AnnouncementDetailState {
  final AnnouncementEntity announcement;
  final AnnouncementReadStats? readStats;

  const AnnouncementDetailLoaded({
    required this.announcement,
    this.readStats,
  });

  @override
  List<Object?> get props => [announcement, readStats];
}

final class AnnouncementDetailError extends AnnouncementDetailState {
  final String message;
  const AnnouncementDetailError(this.message);

  @override
  List<Object?> get props => [message];
}

final class AnnouncementDeleted extends AnnouncementDetailState {
  const AnnouncementDeleted();
}
