import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';

final class CreateAnnouncement {
  final IAnnouncementRepo _repo;

  const CreateAnnouncement({required IAnnouncementRepo repo}) : _repo = repo;

  Future<AnnouncementEntity> call({
    required String groupId,
    required String title,
    required String body,
    bool pinned = false,
  }) {
    if (title.trim().length < 2) {
      throw ArgumentError('Title must be at least 2 characters');
    }
    if (body.trim().isEmpty) {
      throw ArgumentError('Body cannot be empty');
    }
    return _repo.create(
      groupId: groupId,
      title: title.trim(),
      body: body.trim(),
      pinned: pinned,
    );
  }
}
