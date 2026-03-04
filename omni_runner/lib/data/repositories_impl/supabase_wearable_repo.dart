import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/offline/offline_queue.dart';
import 'package:omni_runner/domain/entities/device_link_entity.dart';
import 'package:omni_runner/domain/entities/workout_execution_entity.dart';
import 'package:omni_runner/domain/repositories/i_wearable_repo.dart';

final class SupabaseWearableRepo implements IWearableRepo {
  final SupabaseClient _db;
  final OfflineQueue? _offlineQueue;

  const SupabaseWearableRepo(this._db, {OfflineQueue? offlineQueue})
      : _offlineQueue = offlineQueue;

  static bool _isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('network');
  }

  Future<T> _retry<T>(Future<T> Function() fn, {int maxAttempts = 3}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i == maxAttempts - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    throw StateError('unreachable');
  }

  // ── Device Links ──

  @override
  Future<List<DeviceLinkEntity>> listDeviceLinks(String athleteUserId) async {
    try {
      final rows = await _db
          .from('coaching_device_links')
          .select()
          .eq('athlete_user_id', athleteUserId)
          .order('linked_at', ascending: false);
      return rows.map(_fromDeviceLinkRow).toList();
    } catch (e, st) {
      AppLogger.error('Wearable.listDeviceLinks failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<DeviceLinkEntity> linkDevice({
    required String groupId,
    required String provider,
    String? accessToken,
    String? refreshToken,
  }) async {
    try {
      return await _retry(() async {
        final uid = _db.auth.currentUser!.id;
        final row = await _db.from('coaching_device_links').upsert({
          'group_id': groupId,
          'athlete_user_id': uid,
          'provider': provider,
          'access_token': accessToken,
          'refresh_token': refreshToken,
          'linked_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'athlete_user_id,provider').select().single();
        return _fromDeviceLinkRow(row);
      });
    } catch (e, st) {
      AppLogger.error('Wearable.linkDevice failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> unlinkDevice(String linkId) async {
    try {
      await _db.from('coaching_device_links').delete().eq('id', linkId);
    } catch (e, st) {
      AppLogger.error('Wearable.unlinkDevice failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Workout Payload ──

  @override
  Future<Map<String, dynamic>> generateWorkoutPayload(
      String assignmentId) async {
    try {
      final res = await _db.rpc('fn_generate_workout_payload', params: {
        'p_assignment_id': assignmentId,
      });
      return res as Map<String, dynamic>;
    } catch (e, st) {
      AppLogger.error('Wearable.generateWorkoutPayload failed',
          error: e, stack: st);
      rethrow;
    }
  }

  // ── Executions ──

  @override
  Future<WorkoutExecutionEntity> importExecution({
    String? assignmentId,
    required int durationSeconds,
    int? distanceMeters,
    int? avgPace,
    int? avgHr,
    int? maxHr,
    int? calories,
    String source = 'manual',
    String? providerActivityId,
  }) async {
    try {
      return await _retry(() async {
        final res = await _db.rpc('fn_import_execution', params: {
          'p_assignment_id': assignmentId,
          'p_duration_seconds': durationSeconds,
          'p_distance_meters': distanceMeters,
          'p_avg_pace': avgPace,
          'p_avg_hr': avgHr,
          'p_max_hr': maxHr,
          'p_calories': calories,
          'p_source': source,
          'p_provider_activity_id': providerActivityId,
        });
        final data = res as Map<String, dynamic>;
        if (data['ok'] != true) {
          throw Exception(data['message'] ?? 'Erro ao importar execução');
        }
        final execId = data['data']?['execution_id'] as String?;
        return WorkoutExecutionEntity(
          id: execId ?? '',
          groupId: '',
          assignmentId: assignmentId,
          athleteUserId: _db.auth.currentUser!.id,
          actualDurationSeconds: durationSeconds,
          actualDistanceMeters: distanceMeters,
          avgPace: avgPace,
          avgHr: avgHr,
          maxHr: maxHr,
          calories: calories,
          source: source,
          completedAt: DateTime.now(),
        );
      });
    } catch (e, st) {
      AppLogger.error('Wearable.importExecution failed', error: e, stack: st);
      if (_isNetworkError(e) && _offlineQueue != null) {
        final params = {
          'p_assignment_id': assignmentId,
          'p_duration_seconds': durationSeconds,
          'p_distance_meters': distanceMeters,
          'p_avg_pace': avgPace,
          'p_avg_hr': avgHr,
          'p_max_hr': maxHr,
          'p_calories': calories,
          'p_source': source,
          'p_provider_activity_id': providerActivityId,
        };
        await _offlineQueue.enqueue('fn_import_execution', params);
      }
      rethrow;
    }
  }

  @override
  Future<List<WorkoutExecutionEntity>> listExecutions({
    required String groupId,
    required String athleteUserId,
    int limit = 50,
  }) async {
    try {
      final rows = await _db
          .from('coaching_workout_executions')
          .select(
              '*, coaching_workout_assignments(scheduled_date, coaching_workout_templates(name))')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId)
          .order('completed_at', ascending: false)
          .limit(limit);
      return rows.map(_fromExecutionRow).toList();
    } catch (e, st) {
      AppLogger.error('Wearable.listExecutions failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Mappers ──

  static DeviceLinkEntity _fromDeviceLinkRow(Map<String, dynamic> r) =>
      DeviceLinkEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        athleteUserId: r['athlete_user_id'] as String,
        provider: deviceProviderFromString(r['provider'] as String),
        expiresAt: r['expires_at'] != null
            ? DateTime.parse(r['expires_at'] as String)
            : null,
        linkedAt: DateTime.parse(r['linked_at'] as String),
      );

  static WorkoutExecutionEntity _fromExecutionRow(Map<String, dynamic> r) {
    final assignment =
        r['coaching_workout_assignments'] as Map<String, dynamic>?;
    final template = assignment?['coaching_workout_templates']
        as Map<String, dynamic>?;

    return WorkoutExecutionEntity(
      id: r['id'] as String,
      groupId: r['group_id'] as String,
      assignmentId: r['assignment_id'] as String?,
      athleteUserId: r['athlete_user_id'] as String,
      actualDurationSeconds: r['actual_duration_seconds'] as int?,
      actualDistanceMeters: r['actual_distance_meters'] as int?,
      avgPace: r['avg_pace_seconds_per_km'] as int?,
      avgHr: r['avg_hr'] as int?,
      maxHr: r['max_hr'] as int?,
      calories: r['calories'] as int?,
      source: r['source'] as String,
      completedAt: DateTime.parse(r['completed_at'] as String),
      assignmentTemplateName: template?['name'] as String?,
      assignmentDate: assignment?['scheduled_date'] != null
          ? DateTime.parse(assignment!['scheduled_date'] as String)
          : null,
    );
  }
}
