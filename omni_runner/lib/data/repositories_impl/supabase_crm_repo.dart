import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/athlete_note_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';

final class SupabaseCrmRepo implements ICrmRepo {
  final SupabaseClient _db;

  const SupabaseCrmRepo(this._db);

  // ── Tags ──

  @override
  Future<List<CoachingTagEntity>> listTags(String groupId) async {
    try {
      final rows = await _db
          .from('coaching_tags')
          .select()
          .eq('group_id', groupId)
          .order('name');
      return rows.map(_tagFromRow).toList();
    } on Object catch (e, st) {
      AppLogger.error('Crm.listTags failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CoachingTagEntity> createTag({
    required String groupId,
    required String name,
    String? color,
  }) async {
    try {
      final row = await _db
          .from('coaching_tags')
          .insert({'group_id': groupId, 'name': name, 'color': color})
          .select()
          .single();
      return _tagFromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('Crm.createTag failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> deleteTag(String tagId) async {
    try {
      await _db.from('coaching_tags').delete().eq('id', tagId);
    } on Object catch (e, st) {
      AppLogger.error('Crm.deleteTag failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Athlete Tags ──

  @override
  Future<List<CoachingTagEntity>> getAthleteTags({
    required String groupId,
    required String athleteUserId,
  }) async {
    try {
      final rows = await _db
          .from('coaching_athlete_tags')
          .select('*, coaching_tags(*)')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId);
      return rows.map((r) {
        final tag = r['coaching_tags'] as Map<String, dynamic>;
        return _tagFromRow(tag);
      }).toList();
    } on Object catch (e, st) {
      AppLogger.error('Crm.getAthleteTags failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> assignTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {
    try {
      await _db.from('coaching_athlete_tags').upsert(
        {
          'group_id': groupId,
          'athlete_user_id': athleteUserId,
          'tag_id': tagId,
        },
        onConflict: 'group_id,athlete_user_id,tag_id',
      );
    } on Object catch (e, st) {
      AppLogger.error('Crm.assignTag failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> removeTag({
    required String groupId,
    required String athleteUserId,
    required String tagId,
  }) async {
    try {
      await _db
          .from('coaching_athlete_tags')
          .delete()
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId)
          .eq('tag_id', tagId);
    } on Object catch (e, st) {
      AppLogger.error('Crm.removeTag failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Notes ──

  @override
  Future<List<AthleteNoteEntity>> listNotes({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final rows = await _db
          .from('coaching_athlete_notes')
          .select('*, profiles!created_by(display_name)')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(_noteFromRow).toList();
    } on Object catch (e, st) {
      AppLogger.error('Crm.listNotes failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<AthleteNoteEntity> createNote({
    required String groupId,
    required String athleteUserId,
    required String note,
  }) async {
    try {
      final uid = _db.auth.currentUser!.id;
      final row = await _db.from('coaching_athlete_notes').insert({
        'group_id': groupId,
        'athlete_user_id': athleteUserId,
        'created_by': uid,
        'note': note,
      }).select('*, profiles!created_by(display_name)').single();
      return _noteFromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('Crm.createNote failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> deleteNote(String noteId) async {
    try {
      await _db.from('coaching_athlete_notes').delete().eq('id', noteId);
    } on Object catch (e, st) {
      AppLogger.error('Crm.deleteNote failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Member Status ──

  @override
  Future<MemberStatusEntity?> getStatus({
    required String groupId,
    required String userId,
  }) async {
    try {
      final row = await _db
          .from('coaching_member_status')
          .select()
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .maybeSingle();
      return row == null ? null : _statusFromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('Crm.getStatus failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<MemberStatusEntity> upsertStatus({
    required String groupId,
    required String userId,
    required MemberStatusValue status,
  }) async {
    try {
      final res = await _db.rpc('fn_upsert_member_status', params: {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_status': memberStatusToString(status),
      });
      final data = res as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Failed to upsert status');
      }
      return MemberStatusEntity(
        groupId: groupId,
        userId: userId,
        status: status,
        updatedAt: DateTime.now(),
        updatedBy: _db.auth.currentUser?.id,
      );
    } on Object catch (e, st) {
      AppLogger.error('Crm.upsertStatus failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── CRM List ──

  @override
  Future<List<CrmAthleteView>> listAthletes({
    required String groupId,
    List<String>? tagIds,
    MemberStatusValue? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final memberQuery = _db
          .from('coaching_members')
          .select('user_id, profiles!user_id(display_name, avatar_url)')
          .eq('group_id', groupId)
          .inFilter('role', ['athlete', 'atleta']);

      final members = await memberQuery
          .order('user_id')
          .range(offset, offset + limit - 1);

      if (members.isEmpty) return [];

      final userIds = members.map((m) => m['user_id'] as String).toList();

      final tagsFut = _db
          .from('coaching_athlete_tags')
          .select('athlete_user_id, coaching_tags(*)')
          .eq('group_id', groupId)
          .inFilter('athlete_user_id', userIds);

      final statusFut = _db
          .from('coaching_member_status')
          .select()
          .eq('group_id', groupId)
          .inFilter('user_id', userIds);

      final attendanceFut = _db
          .from('coaching_training_attendance')
          .select('athlete_user_id')
          .eq('group_id', groupId)
          .inFilter('athlete_user_id', userIds);

      final alertsFut = _db
          .from('coaching_alerts')
          .select('user_id')
          .eq('group_id', groupId)
          .inFilter('user_id', userIds)
          .eq('resolved', false);

      final results = await Future.wait([tagsFut, statusFut, attendanceFut, alertsFut]);

      final tagsRows = results[0] as List<dynamic>;
      final statusRows = results[1] as List<dynamic>;
      final attendanceRows = results[2] as List<dynamic>;
      final alertRows = results[3] as List<dynamic>;

      final tagsByUser = <String, List<CoachingTagEntity>>{};
      for (final raw in tagsRows) {
        final r = raw as Map<String, dynamic>;
        final uid = r['athlete_user_id'] as String;
        final tag = _tagFromRow(r['coaching_tags'] as Map<String, dynamic>);
        tagsByUser.putIfAbsent(uid, () => []).add(tag);
      }

      final statusByUser = <String, MemberStatusValue>{};
      for (final raw in statusRows) {
        final r = raw as Map<String, dynamic>;
        statusByUser[r['user_id'] as String] =
            memberStatusFromString(r['status'] as String);
      }

      final attendanceCountByUser = <String, int>{};
      for (final raw in attendanceRows) {
        final r = raw as Map<String, dynamic>;
        final uid = r['athlete_user_id'] as String;
        attendanceCountByUser[uid] = (attendanceCountByUser[uid] ?? 0) + 1;
      }

      final alertUserIds = alertRows
          .map((raw) => (raw as Map<String, dynamic>)['user_id'] as String)
          .toSet();

      var filteredMembers = members;
      if (tagIds != null && tagIds.isNotEmpty) {
        final tagIdSet = tagIds.toSet();
        filteredMembers = members.where((m) {
          final uid = m['user_id'] as String;
          final userTags = tagsByUser[uid] ?? [];
          return userTags.any((t) => tagIdSet.contains(t.id));
        }).toList();
      }

      if (status != null) {
        filteredMembers = filteredMembers.where((m) {
          final uid = m['user_id'] as String;
          return statusByUser[uid] == status;
        }).toList();
      }

      return filteredMembers.map((m) {
        final uid = m['user_id'] as String;
        final profile = m['profiles'] as Map<String, dynamic>?;
        return CrmAthleteView(
          userId: uid,
          displayName: profile?['display_name'] as String? ?? 'Atleta',
          avatarUrl: profile?['avatar_url'] as String?,
          status: statusByUser[uid],
          tags: tagsByUser[uid] ?? [],
          attendanceCount: attendanceCountByUser[uid] ?? 0,
          hasActiveAlerts: alertUserIds.contains(uid),
        );
      }).toList();
    } on Object catch (e, st) {
      AppLogger.error('Crm.listAthletes failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Mappers ──

  static CoachingTagEntity _tagFromRow(Map<String, dynamic> r) =>
      CoachingTagEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        name: r['name'] as String,
        color: r['color'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  static AthleteNoteEntity _noteFromRow(Map<String, dynamic> r) {
    final profile = r['profiles'] as Map<String, dynamic>?;
    return AthleteNoteEntity(
      id: r['id'] as String,
      groupId: r['group_id'] as String,
      athleteUserId: r['athlete_user_id'] as String,
      createdBy: r['created_by'] as String,
      note: r['note'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      authorDisplayName: profile?['display_name'] as String?,
    );
  }

  static MemberStatusEntity _statusFromRow(Map<String, dynamic> r) =>
      MemberStatusEntity(
        groupId: r['group_id'] as String,
        userId: r['user_id'] as String,
        status: memberStatusFromString(r['status'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        updatedBy: r['updated_by'] as String?,
      );
}
