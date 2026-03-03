import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';
import 'package:omni_runner/domain/usecases/announcements/mark_announcement_read.dart';

class _FakeAnnouncementRepo implements IAnnouncementRepo {
  final Set<String> markedRead = {};
  bool shouldThrow = false;

  @override
  Future<void> markRead(String announcementId) async {
    if (shouldThrow) throw Exception('Not found');
    markedRead.add(announcementId);
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
  Future<AnnouncementReadStats> getReadStats(String announcementId) async =>
      const AnnouncementReadStats(
          totalMembers: 0, readCount: 0, readRate: 0.0);
}

void main() {
  late _FakeAnnouncementRepo repo;
  late MarkAnnouncementRead usecase;

  setUp(() {
    repo = _FakeAnnouncementRepo();
    usecase = MarkAnnouncementRead(repo: repo);
  });

  test('marks announcement as read', () async {
    await usecase.call('ann-1');
    expect(repo.markedRead, contains('ann-1'));
  });

  test('marking same announcement twice is idempotent', () async {
    await usecase.call('ann-1');
    await usecase.call('ann-1');
    expect(repo.markedRead.length, 1);
  });

  test('propagates repo exceptions', () {
    repo.shouldThrow = true;

    expect(
      () => usecase.call('ann-1'),
      throwsA(isA<Exception>()),
    );
  });
}
