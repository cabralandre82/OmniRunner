import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';

final class ListAnnouncements {
  final IAnnouncementRepo _repo;

  const ListAnnouncements({required IAnnouncementRepo repo}) : _repo = repo;

  Future<List<AnnouncementEntity>> call({
    required String groupId,
    int limit = 50,
    int offset = 0,
  }) =>
      _repo.listByGroup(groupId: groupId, limit: limit, offset: offset);
}
