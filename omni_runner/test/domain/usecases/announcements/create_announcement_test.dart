import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/usecases/announcements/create_announcement.dart';

class _FakeAnnouncementRepo implements IAnnouncementRepo {
  AnnouncementEntity? saved;

  @override
  Future<AnnouncementEntity> create({
    required String groupId,
    required String title,
    required String body,
    bool pinned = false,
  }) async {
    final now = DateTime.now();
    final entity = AnnouncementEntity(
      id: 'ann-1',
      groupId: groupId,
      createdBy: 'coach-1',
      title: title,
      body: body,
      pinned: pinned,
      createdAt: now,
      updatedAt: now,
    );
    saved = entity;
    return entity;
  }

  @override
  Future<List<AnnouncementEntity>> listByGroup({
    required String groupId,
    int limit = 50,
    int offset = 0,
  }) async =>
      [];
  @override
  Future<AnnouncementEntity?> getById(String id) async => null;
  @override
  Future<AnnouncementEntity> update(AnnouncementEntity announcement) async =>
      announcement;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> markRead(String announcementId) async {}
  @override
  Future<AnnouncementReadStats> getReadStats(String announcementId) async =>
      const AnnouncementReadStats(
          totalMembers: 0, readCount: 0, readRate: 0.0);
}

void main() {
  late _FakeAnnouncementRepo repo;
  late CreateAnnouncement usecase;

  setUp(() {
    repo = _FakeAnnouncementRepo();
    usecase = CreateAnnouncement(repo: repo);
  });

  test('creates announcement with valid data', () async {
    final result = await usecase.call(
      groupId: 'group-1',
      title: 'Race Day',
      body: 'We have a race this weekend!',
      pinned: true,
    );

    expect(result.title, 'Race Day');
    expect(result.body, 'We have a race this weekend!');
    expect(result.pinned, isTrue);
    expect(result.groupId, 'group-1');
    expect(repo.saved, isNotNull);
  });

  test('creates non-pinned announcement by default', () async {
    final result = await usecase.call(
      groupId: 'group-1',
      title: 'Update',
      body: 'General update for the group',
    );

    expect(result.pinned, isFalse);
  });

  test('trims title and body whitespace', () async {
    final result = await usecase.call(
      groupId: 'group-1',
      title: '  Important  ',
      body: '  Please read  ',
    );

    expect(result.title, 'Important');
    expect(result.body, 'Please read');
  });

  test('throws when title is too short', () {
    expect(
      () => usecase.call(
        groupId: 'group-1',
        title: 'X',
        body: 'Some body text',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when title is only whitespace', () {
    expect(
      () => usecase.call(
        groupId: 'group-1',
        title: '   ',
        body: 'Some body text',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when body is empty', () {
    expect(
      () => usecase.call(
        groupId: 'group-1',
        title: 'Valid Title',
        body: '',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when body is only whitespace', () {
    expect(
      () => usecase.call(
        groupId: 'group-1',
        title: 'Valid Title',
        body: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
