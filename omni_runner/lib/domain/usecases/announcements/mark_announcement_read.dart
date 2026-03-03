import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';

final class MarkAnnouncementRead {
  final IAnnouncementRepo _repo;

  const MarkAnnouncementRead({required IAnnouncementRepo repo}) : _repo = repo;

  Future<void> call(String announcementId) =>
      _repo.markRead(announcementId);
}
