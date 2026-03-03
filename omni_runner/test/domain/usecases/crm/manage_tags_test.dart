import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';

class _FakeCrmRepo implements ICrmRepo {
  final List<CoachingTagEntity> tags = [];
  final Map<String, List<String>> athleteTags = {};
  int _seq = 0;

  @override
  Future<List<CoachingTagEntity>> listTags(String groupId) async =>
      tags.where((t) => t.groupId == groupId).toList();

  @override
  Future<CoachingTagEntity> createTag({
    required String groupId,
    required String name,
    String? color,
  }) async {
    final tag = CoachingTagEntity(
      id: 'tag-${++_seq}',
      groupId: groupId,
      name: name,
      color: color,
      createdAt: DateTime.now(),
    );
    tags.add(tag);
    return tag;
  }

  @override
  Future<void> deleteTag(String tagId) async {
    tags.removeWhere((t) => t.id == tagId);
  }

  @override
  Future<void> assignTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {
    athleteTags.putIfAbsent(athleteUserId, () => []).add(tagId);
  }

  @override
  Future<void> removeTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {
    athleteTags[athleteUserId]?.remove(tagId);
  }

  @override
  Future<List<CoachingTagEntity>> getAthleteTags({
    required String groupId,
    required String athleteUserId,
  }) async {
    final ids = athleteTags[athleteUserId] ?? [];
    return tags.where((t) => ids.contains(t.id)).toList();
  }

  @override
  Future<List<AthleteNoteEntity>> listNotes({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<AthleteNoteEntity> createNote({
    required String groupId,
    required String athleteUserId,
    required String note,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteNote(String noteId) async {}
  @override
  Future<MemberStatusEntity?> getStatus({
    required String groupId,
    required String userId,
  }) async =>
      null;
  @override
  Future<MemberStatusEntity> upsertStatus({
    required String groupId,
    required String userId,
    required MemberStatusValue status,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<CrmAthleteView>> listAthletes({
    required String groupId,
    List<String>? tagIds,
    MemberStatusValue? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
}

void main() {
  late _FakeCrmRepo repo;
  late ManageTags usecase;

  setUp(() {
    repo = _FakeCrmRepo();
    usecase = ManageTags(repo: repo);
  });

  test('creates a tag', () async {
    final tag = await usecase.create(
      groupId: 'group-1',
      name: 'Beginner',
      color: '#FF0000',
    );

    expect(tag.name, 'Beginner');
    expect(tag.color, '#FF0000');
    expect(tag.groupId, 'group-1');
  });

  test('lists tags for a group', () async {
    await usecase.create(groupId: 'group-1', name: 'A');
    await usecase.create(groupId: 'group-1', name: 'B');
    await usecase.create(groupId: 'group-2', name: 'C');

    final result = await usecase.list('group-1');
    expect(result.length, 2);
  });

  test('deletes a tag', () async {
    final tag = await usecase.create(groupId: 'group-1', name: 'ToDelete');
    await usecase.delete(tag.id);

    final remaining = await usecase.list('group-1');
    expect(remaining, isEmpty);
  });

  test('assigns and retrieves tag for athlete', () async {
    final tag = await usecase.create(groupId: 'group-1', name: 'Elite');
    await usecase.assign(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      tagId: tag.id,
    );

    final tags = await usecase.forAthlete(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(tags.length, 1);
    expect(tags.first.name, 'Elite');
  });

  test('removes tag from athlete', () async {
    final tag = await usecase.create(groupId: 'group-1', name: 'Temp');
    await usecase.assign(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      tagId: tag.id,
    );
    await usecase.remove(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      tagId: tag.id,
    );

    final tags = await usecase.forAthlete(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(tags, isEmpty);
  });

  test('throws when tag name is empty', () {
    expect(
      () => usecase.create(groupId: 'group-1', name: ''),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when tag name is only whitespace', () {
    expect(
      () => usecase.create(groupId: 'group-1', name: '   '),
      throwsA(isA<ArgumentError>()),
    );
  });
}
