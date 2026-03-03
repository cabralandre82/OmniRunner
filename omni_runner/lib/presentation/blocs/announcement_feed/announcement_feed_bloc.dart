import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/usecases/announcements/list_announcements.dart';
import 'package:omni_runner/domain/usecases/announcements/mark_announcement_read.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_event.dart';
import 'package:omni_runner/presentation/blocs/announcement_feed/announcement_feed_state.dart';

class AnnouncementFeedBloc
    extends Bloc<AnnouncementFeedEvent, AnnouncementFeedState> {
  final ListAnnouncements _listAnnouncements;
  final MarkAnnouncementRead _markAnnouncementRead;
  String _groupId = '';

  AnnouncementFeedBloc({
    required ListAnnouncements listAnnouncements,
    required MarkAnnouncementRead markAnnouncementRead,
  })  : _listAnnouncements = listAnnouncements,
        _markAnnouncementRead = markAnnouncementRead,
        super(const AnnouncementFeedInitial()) {
    on<LoadAnnouncements>(_onLoad);
    on<RefreshAnnouncements>(_onRefresh);
    on<MarkAsRead>(_onMarkAsRead);
  }

  Future<void> _onLoad(
    LoadAnnouncements event,
    Emitter<AnnouncementFeedState> emit,
  ) async {
    _groupId = event.groupId;
    emit(const AnnouncementFeedLoading());
    try {
      final announcements = await _listAnnouncements(groupId: _groupId);
      final unreadCount = announcements.where((a) => !a.isRead).length;
      emit(AnnouncementFeedLoaded(
        announcements: announcements,
        unreadCount: unreadCount,
      ));
    } on Exception catch (e) {
      emit(AnnouncementFeedError('Não foi possível carregar os anúncios: $e'));
    }
  }

  Future<void> _onRefresh(
    RefreshAnnouncements _,
    Emitter<AnnouncementFeedState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    try {
      final announcements = await _listAnnouncements(groupId: _groupId);
      final unreadCount = announcements.where((a) => !a.isRead).length;
      emit(AnnouncementFeedLoaded(
        announcements: announcements,
        unreadCount: unreadCount,
      ));
    } on Exception catch (e, st) {
      AppLogger.error('Failed to refresh announcements', tag: 'AnnouncementFeedBloc', error: e, stack: st);
    }
  }

  Future<void> _onMarkAsRead(
    MarkAsRead event,
    Emitter<AnnouncementFeedState> emit,
  ) async {
    final current = state;
    if (current is! AnnouncementFeedLoaded) return;

    try {
      await _markAnnouncementRead(event.announcementId);

      final updated = current.announcements.map((a) {
        if (a.id == event.announcementId) return a.copyWith(isRead: true);
        return a;
      }).toList();

      final unreadCount = updated.where((a) => !a.isRead).length;
      emit(AnnouncementFeedLoaded(
        announcements: updated,
        unreadCount: unreadCount,
      ));
    } on Exception catch (e, st) {
      AppLogger.error('Failed to mark announcement as read', tag: 'AnnouncementFeedBloc', error: e, stack: st);
    }
  }
}
