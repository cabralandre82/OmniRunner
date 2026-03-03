import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/training_attendance_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';

final class SupabaseTrainingAttendanceRepo implements ITrainingAttendanceRepo {
  final SupabaseClient _db;

  const SupabaseTrainingAttendanceRepo(this._db);

  @override
  Future<MarkAttendanceResult> markAttendance({
    required String sessionId,
    required String athleteUserId,
    String? nonce,
  }) async {
    try {
      final res = await _db.rpc('fn_mark_attendance', params: {
        'p_session_id': sessionId,
        'p_athlete_user_id': athleteUserId,
        'p_nonce': nonce,
      });

      final data = res as Map<String, dynamic>;
      final ok = data['ok'] as bool;
      final status = data['status'] as String;

      if (!ok) {
        return AttendanceFailed(status, data['message'] as String? ?? status);
      }

      if (status == 'already_present') {
        return const AttendanceAlreadyPresent();
      }

      return AttendanceInserted(data['attendance_id'] as String);
    } catch (e, st) {
      AppLogger.error('TrainingAttendance.markAttendance failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<CheckinToken> issueCheckinToken({
    required String sessionId,
    int ttlSeconds = 120,
  }) async {
    try {
      final res = await _db.rpc('fn_issue_checkin_token', params: {
        'p_session_id': sessionId,
        'p_ttl_seconds': ttlSeconds,
      });

      final data = res as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Failed to issue checkin token');
      }

      return CheckinToken(
        sessionId: data['session_id'] as String,
        athleteUserId: data['athlete_user_id'] as String,
        groupId: data['group_id'] as String,
        nonce: data['nonce'] as String,
        expiresAtMs: (data['expires_at'] as num).toInt(),
      );
    } catch (e, st) {
      AppLogger.error('TrainingAttendance.issueCheckinToken failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<TrainingAttendanceEntity>> listBySession(
      String sessionId) async {
    try {
      final rows = await _db
          .from('coaching_training_attendance')
          .select('*, profiles!athlete_user_id(display_name)')
          .eq('session_id', sessionId)
          .order('checked_at');
      return rows.map(_fromRow).toList();
    } catch (e, st) {
      AppLogger.error('TrainingAttendance.listBySession failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<TrainingAttendanceEntity>> listByAthlete({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final rows = await _db
          .from('coaching_training_attendance')
          .select('*, coaching_training_sessions!inner(title, starts_at)')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId)
          .order('checked_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(_fromRow).toList();
    } catch (e, st) {
      AppLogger.error('TrainingAttendance.listByAthlete failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<int> countBySession(String sessionId) async {
    try {
      final res = await _db
          .from('coaching_training_attendance')
          .select()
          .eq('session_id', sessionId)
          .count(CountOption.exact);
      return res.count;
    } catch (e, st) {
      AppLogger.error('TrainingAttendance.countBySession failed', error: e, stack: st);
      rethrow;
    }
  }

  static TrainingAttendanceEntity _fromRow(Map<String, dynamic> r) {
    final profile = r['profiles'] as Map<String, dynamic>?;
    final sessionData = r['coaching_training_sessions'];
    String? sessionTitle;
    DateTime? sessionStartsAt;
    if (sessionData is Map<String, dynamic>) {
      sessionTitle = sessionData['title'] as String?;
      final s = sessionData['starts_at'];
      if (s != null) sessionStartsAt = DateTime.parse(s as String);
    }
    return TrainingAttendanceEntity(
      id: r['id'] as String,
      groupId: r['group_id'] as String,
      sessionId: r['session_id'] as String,
      athleteUserId: r['athlete_user_id'] as String,
      checkedBy: r['checked_by'] as String,
      checkedAt: DateTime.parse(r['checked_at'] as String),
      status: attendanceStatusFromString(r['status'] as String),
      method: (r['method'] as String) == 'manual'
          ? CheckinMethod.manual
          : CheckinMethod.qr,
      athleteDisplayName: profile?['display_name'] as String?,
      sessionTitle: sessionTitle,
      sessionStartsAt: sessionStartsAt,
    );
  }
}
