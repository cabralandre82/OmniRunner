import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

final class ManageTags {
  final ICrmRepo _repo;

  const ManageTags({required ICrmRepo repo}) : _repo = repo;

  Future<List<CoachingTagEntity>> list(String groupId) =>
      _repo.listTags(groupId);

  Future<CoachingTagEntity> create({
    required String groupId,
    required String name,
    String? color,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Tag name cannot be empty');
    return _repo.createTag(groupId: groupId, name: name.trim(), color: color);
  }

  Future<void> delete(String tagId) => _repo.deleteTag(tagId);

  Future<void> assign({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) =>
      _repo.assignTag(
          groupId: groupId, athleteUserId: athleteUserId, tagId: tagId);

  Future<void> remove({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) =>
      _repo.removeTag(
          groupId: groupId, athleteUserId: athleteUserId, tagId: tagId);

  Future<List<CoachingTagEntity>> forAthlete({
    required String groupId,
    required String athleteUserId,
  }) =>
      _repo.getAthleteTags(groupId: groupId, athleteUserId: athleteUserId);
}
