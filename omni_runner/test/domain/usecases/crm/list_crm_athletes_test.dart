import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/list_crm_athletes.dart';

class _FakeCrmRepo implements ICrmRepo {
  final List<CrmAthleteView> athletes = [];
  String? lastGroupId;
  List<String>? lastTagIds;
  MemberStatusValue? lastStatus;
  int? lastLimit;
  int? lastOffset;

  @override
  Future<List<CrmAthleteView>> listAthletes({
    required String groupId,
    List<String>? tagIds,
    MemberStatusValue? status,
    int limit = 50,
    int offset = 0,
  }) async {
    lastGroupId = groupId;
    lastTagIds = tagIds;
    lastStatus = status;
    lastLimit = limit;
    lastOffset = offset;
    return athletes;
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
}

void main() {
  late _FakeCrmRepo repo;
  late ListCrmAthletes usecase;

  setUp(() {
    repo = _FakeCrmRepo();
    usecase = ListCrmAthletes(repo: repo);
  });

  test('returns empty list when no athletes', () async {
    final result = await usecase.call(groupId: 'group-1');
    expect(result, isEmpty);
  });

  test('returns athletes from repo', () async {
    repo.athletes.addAll([
      const CrmAthleteView(userId: 'u1', displayName: 'Alice'),
      const CrmAthleteView(userId: 'u2', displayName: 'Bob'),
    ]);

    final result = await usecase.call(groupId: 'group-1');
    expect(result.length, 2);
    expect(result.first.displayName, 'Alice');
  });

  test('passes filter parameters to repo', () async {
    await usecase.call(
      groupId: 'group-1',
      tagIds: ['tag-1', 'tag-2'],
      status: MemberStatusValue.active,
      limit: 10,
      offset: 5,
    );

    expect(repo.lastGroupId, 'group-1');
    expect(repo.lastTagIds, ['tag-1', 'tag-2']);
    expect(repo.lastStatus, MemberStatusValue.active);
    expect(repo.lastLimit, 10);
    expect(repo.lastOffset, 5);
  });

  test('uses default limit and offset', () async {
    await usecase.call(groupId: 'group-1');

    expect(repo.lastLimit, 50);
    expect(repo.lastOffset, 0);
    expect(repo.lastTagIds, isNull);
    expect(repo.lastStatus, isNull);
  });
}
