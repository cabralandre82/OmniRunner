import 'package:omni_runner/domain/entities/announcement_entity.dart';

/// Read stats returned by the RPC.
final class AnnouncementReadStats {
  final int totalMembers;
  final int readCount;
  final double readRate;

  const AnnouncementReadStats({
    required this.totalMembers,
    required this.readCount,
    required this.readRate,
  });
}

abstract interface class IAnnouncementRepo {
  /// List announcements for a group (pinned first, then by date desc).
  /// Includes isRead flag for the current user.
  Future<List<AnnouncementEntity>> listByGroup({
    required String groupId,
    int limit = 50,
    int offset = 0,
  });

  Future<AnnouncementEntity?> getById(String id);

  Future<AnnouncementEntity> create({
    required String groupId,
    required String title,
    required String body,
    bool pinned = false,
  });

  Future<AnnouncementEntity> update(AnnouncementEntity announcement);

  Future<void> delete(String id);

  /// Mark as read for the current user (idempotent).
  Future<void> markRead(String announcementId);

  /// Get read stats for a specific announcement (staff).
  Future<AnnouncementReadStats> getReadStats(String announcementId);
}
