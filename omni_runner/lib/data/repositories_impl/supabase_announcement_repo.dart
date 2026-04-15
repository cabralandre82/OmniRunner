import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/announcement_entity.dart';
import 'package:omni_runner/domain/repositories/i_announcement_repo.dart';

final class SupabaseAnnouncementRepo implements IAnnouncementRepo {
  final SupabaseClient _db;

  const SupabaseAnnouncementRepo(this._db);

  @override
  Future<List<AnnouncementEntity>> listByGroup({
    required String groupId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final uid = _db.auth.currentUser?.id;

      final rows = await _db
          .from('coaching_announcements')
          .select('*, profiles!created_by(display_name)')
          .eq('group_id', groupId)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      if (rows.isEmpty || uid == null) {
        return rows.map((r) => _fromRow(r, isRead: false)).toList();
      }

      final ids = rows.map((r) => r['id'] as String).toList();
      final readRows = await _db
          .from('coaching_announcement_reads')
          .select('announcement_id')
          .eq('user_id', uid)
          .inFilter('announcement_id', ids);
      final readIds = readRows
          .map((r) => r['announcement_id'] as String)
          .toSet();

      return rows
          .map((r) => _fromRow(r, isRead: readIds.contains(r['id'] as String)))
          .toList();
    } on Object catch (e, st) {
      AppLogger.error('Announcement.listByGroup failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<AnnouncementEntity?> getById(String id) async {
    try {
      final uid = _db.auth.currentUser?.id;
      final row = await _db
          .from('coaching_announcements')
          .select('*, profiles!created_by(display_name)')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;

      bool isRead = false;
      if (uid != null) {
        final readRow = await _db
            .from('coaching_announcement_reads')
            .select('announcement_id')
            .eq('announcement_id', id)
            .eq('user_id', uid)
            .maybeSingle();
        isRead = readRow != null;
      }
      return _fromRow(row, isRead: isRead);
    } on Object catch (e, st) {
      AppLogger.error('Announcement.getById failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<AnnouncementEntity> create({
    required String groupId,
    required String title,
    required String body,
    bool pinned = false,
  }) async {
    try {
      final uid = _db.auth.currentUser!.id;
      final row = await _db.from('coaching_announcements').insert({
        'group_id': groupId,
        'created_by': uid,
        'title': title,
        'body': body,
        'pinned': pinned,
      }).select('*, profiles!created_by(display_name)').single();
      return _fromRow(row, isRead: true);
    } on Object catch (e, st) {
      AppLogger.error('Announcement.create failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<AnnouncementEntity> update(AnnouncementEntity a) async {
    try {
      final row = await _db
          .from('coaching_announcements')
          .update({
            'title': a.title,
            'body': a.body,
            'pinned': a.pinned,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', a.id)
          .select('*, profiles!created_by(display_name)')
          .single();
      return _fromRow(row, isRead: a.isRead);
    } on Object catch (e, st) {
      AppLogger.error('Announcement.update failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _db.from('coaching_announcements').delete().eq('id', id);
    } on Object catch (e, st) {
      AppLogger.error('Announcement.delete failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> markRead(String announcementId) async {
    try {
      final res = await _db.rpc('fn_mark_announcement_read', params: {
        'p_announcement_id': announcementId,
      });
      final data = res as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Failed to mark read');
      }
    } on Object catch (e, st) {
      AppLogger.error('Announcement.markRead failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<AnnouncementReadStats> getReadStats(String announcementId) async {
    try {
      final res = await _db.rpc('fn_announcement_read_stats', params: {
        'p_announcement_id': announcementId,
      });
      final data = res as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Failed to get stats');
      }
      return AnnouncementReadStats(
        totalMembers: (data['total_members'] as num).toInt(),
        readCount: (data['read_count'] as num).toInt(),
        readRate: (data['read_rate'] as num).toDouble(),
      );
    } on Object catch (e, st) {
      AppLogger.error('Announcement.getReadStats failed', error: e, stack: st);
      rethrow;
    }
  }

  static AnnouncementEntity _fromRow(
    Map<String, dynamic> r, {
    required bool isRead,
  }) {
    final profile = r['profiles'] as Map<String, dynamic>?;
    return AnnouncementEntity(
      id: r['id'] as String,
      groupId: r['group_id'] as String,
      createdBy: r['created_by'] as String,
      title: r['title'] as String,
      body: r['body'] as String,
      pinned: r['pinned'] as bool? ?? false,
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
      authorDisplayName: profile?['display_name'] as String?,
      isRead: isRead,
    );
  }
}
