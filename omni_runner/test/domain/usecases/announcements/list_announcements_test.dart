import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/usecases/announcements/list_announcements.dart';

AnnouncementEntity _announcement(String id, String groupId) =>
    AnnouncementEntity(
      id: id,
      groupId: groupId,
      createdBy: 'coach-1',
      title: 'Announcement $id',
      body: 'Body of $id',
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

class _FakeAnnouncementRepo implements IAnnouncementRepo {
  final List<AnnouncementEntity> announcements = [];
  String? lastGroupId;
  int? lastLimit;
  int? lastOffset;

  @override
  Future<List<AnnouncementEntity>> listByGroup({
    required String groupId,
    int limit = 50,
    int offset = 0,
  }) async {
    lastGroupId = groupId;
    lastLimit = limit;
    lastOffset = offset;
    return announcements.where((a) => a.groupId == groupId).toList();
  }

  @override
  Future<AnnouncementEntity?> getById(String id) async => null;
  @override
  Future<AnnouncementEntity> create({
    required String groupId,
    required String title,
    required String body,
    bool pinned = false,
  }) async =>
      throw UnimplementedError();
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
  late ListAnnouncements usecase;

  setUp(() {
    repo = _FakeAnnouncementRepo();
    usecase = ListAnnouncements(repo: repo);
  });

  test('returns empty list when no announcements exist', () async {
    final result = await usecase.call(groupId: 'group-1');
    expect(result, isEmpty);
  });

  test('returns announcements for the given group', () async {
    repo.announcements.addAll([
      _announcement('a1', 'group-1'),
      _announcement('a2', 'group-1'),
      _announcement('a3', 'group-2'),
    ]);

    final result = await usecase.call(groupId: 'group-1');
    expect(result.length, 2);
    expect(result.every((a) => a.groupId == 'group-1'), isTrue);
  });

  test('passes pagination parameters to repo', () async {
    await usecase.call(groupId: 'group-1', limit: 10, offset: 5);

    expect(repo.lastGroupId, 'group-1');
    expect(repo.lastLimit, 10);
    expect(repo.lastOffset, 5);
  });

  test('uses default limit and offset', () async {
    await usecase.call(groupId: 'group-1');

    expect(repo.lastLimit, 50);
    expect(repo.lastOffset, 0);
  });
}
