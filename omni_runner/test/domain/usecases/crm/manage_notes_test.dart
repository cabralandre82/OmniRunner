import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/manage_notes.dart';

class _FakeCrmRepo implements ICrmRepo {
  final List<AthleteNoteEntity> notes = [];
  int _seq = 0;

  @override
  Future<List<AthleteNoteEntity>> listNotes({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async =>
      notes
          .where(
              (n) => n.groupId == groupId && n.athleteUserId == athleteUserId)
          .skip(offset)
          .take(limit)
          .toList();

  @override
  Future<AthleteNoteEntity> createNote({
    required String groupId,
    required String athleteUserId,
    required String note,
  }) async {
    final entity = AthleteNoteEntity(
      id: 'note-${++_seq}',
      groupId: groupId,
      athleteUserId: athleteUserId,
      createdBy: 'coach-1',
      note: note,
      createdAt: DateTime.now(),
    );
    notes.add(entity);
    return entity;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((n) => n.id == noteId);
  }

  @override
  Future<List<CoachingTagEntity>> listTags(String groupId) async => [];
  @override
  Future<CoachingTagEntity> createTag({
    required String groupId,
    required String name,
    String? color,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteTag(String tagId) async {}
  @override
  Future<List<CoachingTagEntity>> getAthleteTags({
    required String groupId,
    required String athleteUserId,
  }) async =>
      [];
  @override
  Future<void> assignTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {}
  @override
  Future<void> removeTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {}
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
  late ManageNotes usecase;

  setUp(() {
    repo = _FakeCrmRepo();
    usecase = ManageNotes(repo: repo);
  });

  test('creates a note', () async {
    final note = await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      note: 'Great progress this week',
    );

    expect(note.note, 'Great progress this week');
    expect(note.athleteUserId, 'athlete-1');
    expect(note.groupId, 'group-1');
  });

  test('lists notes for an athlete', () async {
    await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      note: 'Note 1',
    );
    await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      note: 'Note 2',
    );
    await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-2',
      note: 'Other note',
    );

    final result = await usecase.list(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(result.length, 2);
  });

  test('deletes a note', () async {
    final note = await usecase.create(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
      note: 'To be removed',
    );
    await usecase.delete(note.id);

    final remaining = await usecase.list(
      groupId: 'group-1',
      athleteUserId: 'athlete-1',
    );
    expect(remaining, isEmpty);
  });

  test('returns empty list for athlete with no notes', () async {
    final result = await usecase.list(
      groupId: 'group-1',
      athleteUserId: 'athlete-99',
    );
    expect(result, isEmpty);
  });

  test('throws when note is empty', () {
    expect(
      () => usecase.create(
        groupId: 'group-1',
        athleteUserId: 'athlete-1',
        note: '',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when note is only whitespace', () {
    expect(
      () => usecase.create(
        groupId: 'group-1',
        athleteUserId: 'athlete-1',
        note: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
