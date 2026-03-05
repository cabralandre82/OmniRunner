import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/workout_template_entity.dart';
import 'package:omni_runner/domain/entities/workout_assignment_entity.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';

final class SupabaseWorkoutRepo implements IWorkoutRepo {
  final SupabaseClient _db;

  const SupabaseWorkoutRepo(this._db);

  // ── Templates ──

  @override
  Future<WorkoutTemplateEntity> createTemplate(
      WorkoutTemplateEntity template) async {
    try {
      final row = await _db.from('coaching_workout_templates').insert({
        'id': template.id,
        'group_id': template.groupId,
        'name': template.name,
        'description': template.description,
        'created_by': template.createdBy,
      }).select('id, group_id, name, description, created_by, created_at, updated_at').single();
      return _fromTemplateRow(row);
    } catch (e, st) {
      AppLogger.error('Workout.createTemplate failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<WorkoutTemplateEntity> updateTemplate(
      WorkoutTemplateEntity template) async {
    try {
      final row = await _db
          .from('coaching_workout_templates')
          .update({
            'name': template.name,
            'description': template.description,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', template.id)
          .eq('updated_at', template.updatedAt.toUtc().toIso8601String())
          .select('id, group_id, name, description, created_by, created_at, updated_at')
          .maybeSingle();
      if (row == null) {
        throw Exception(
          'Conflito: outro usuário editou este template. '
          'Recarregue e tente novamente.',
        );
      }
      return _fromTemplateRow(row);
    } catch (e, st) {
      AppLogger.error('Workout.updateTemplate failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _db
          .from('coaching_workout_templates')
          .delete()
          .eq('id', templateId);
    } catch (e, st) {
      AppLogger.error('Workout.deleteTemplate failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<WorkoutTemplateEntity>> listTemplates(String groupId) async {
    try {
      final rows = await _db
          .from('coaching_workout_templates')
          .select('id, group_id, name, description, created_by, created_at, updated_at')
          .eq('group_id', groupId)
          .order('name');
      return rows.map(_fromTemplateRow).toList();
    } catch (e, st) {
      AppLogger.error('Workout.listTemplates failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<WorkoutTemplateEntity?> getTemplateById(String templateId) async {
    try {
      final row = await _db
          .from('coaching_workout_templates')
          .select('id, group_id, name, description, created_by, created_at, updated_at')
          .eq('id', templateId)
          .maybeSingle();
      if (row == null) return null;

      final blockRows = await _db
          .from('coaching_workout_blocks')
          .select('id, template_id, order_index, block_type, duration_seconds, distance_meters, target_pace_seconds_per_km, target_pace_min_sec_per_km, target_pace_max_sec_per_km, target_hr_zone, target_hr_min, target_hr_max, rpe_target, repeat_count, notes')
          .eq('template_id', templateId)
          .order('order_index');
      final blocks = blockRows.map(_fromBlockRow).toList();

      return _fromTemplateRow(row, blocks: blocks);
    } catch (e, st) {
      AppLogger.error('Workout.getTemplateById failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Blocks ──

  @override
  Future<void> saveBlocks(
      String templateId, List<WorkoutBlockEntity> blocks) async {
    try {
      await _db
          .from('coaching_workout_blocks')
          .delete()
          .eq('template_id', templateId);

      if (blocks.isNotEmpty) {
        await _db.from('coaching_workout_blocks').insert(
              blocks
                  .map((b) => {
                        'id': b.id,
                        'template_id': templateId,
                        'order_index': b.orderIndex,
                        'block_type': workoutBlockTypeToString(b.blockType),
                        'duration_seconds': b.durationSeconds,
                        'distance_meters': b.distanceMeters,
                        'target_pace_min_sec_per_km': b.targetPaceMinSecPerKm,
                        'target_pace_max_sec_per_km': b.targetPaceMaxSecPerKm,
                        'target_hr_zone': b.targetHrZone,
                        'target_hr_min': b.targetHrMin,
                        'target_hr_max': b.targetHrMax,
                        'rpe_target': b.rpeTarget,
                        'repeat_count': b.repeatCount,
                        'notes': b.notes,
                      })
                  .toList(),
            );
      }
    } catch (e, st) {
      AppLogger.error('Workout.saveBlocks failed', error: e, stack: st);
      rethrow;
    }
  }

  // ── Assignments ──

  @override
  Future<WorkoutAssignmentEntity> assignWorkout({
    required String templateId,
    required String athleteUserId,
    required DateTime scheduledDate,
    String? notes,
  }) async {
    try {
      final res = await _db.rpc('fn_assign_workout', params: {
        'p_template_id': templateId,
        'p_athlete_user_id': athleteUserId,
        'p_scheduled_date':
            '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}',
        'p_notes': notes,
      });
      final rpc = res as Map<String, dynamic>;

      if (rpc['ok'] != true) {
        throw Exception(
            rpc['message'] as String? ?? rpc['code'] as String? ?? 'Erro ao atribuir treino');
      }

      final assignmentId = rpc['data']?['assignment_id'] as String?;
      if (assignmentId == null) {
        throw Exception('RPC retornou sem assignment_id');
      }

      final row = await _db
          .from('coaching_workout_assignments')
          .select('*, coaching_workout_templates(name)')
          .eq('id', assignmentId)
          .single();
      return _fromAssignmentRow(row);
    } catch (e, st) {
      AppLogger.error('Workout.assignWorkout failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _db
          .from('coaching_workout_assignments')
          .select(
              '*, coaching_workout_templates(name), profiles!athlete_user_id(display_name)')
          .eq('group_id', groupId);

      if (from != null) {
        query =
            query.gte('scheduled_date', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query =
            query.lte('scheduled_date', to.toUtc().toIso8601String());
      }

      final rows = await query
          .order('scheduled_date', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(_fromAssignmentRow).toList();
    } catch (e, st) {
      AppLogger.error('Workout.listAssignmentsByGroup failed',
          error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<WorkoutAssignmentEntity>> listAssignmentsByAthlete({
    required String groupId,
    required String athleteUserId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _db
          .from('coaching_workout_assignments')
          .select('*, coaching_workout_templates(name)')
          .eq('group_id', groupId)
          .eq('athlete_user_id', athleteUserId);

      if (from != null) {
        query =
            query.gte('scheduled_date', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query =
            query.lte('scheduled_date', to.toUtc().toIso8601String());
      }

      final rows = await query
          .order('scheduled_date', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(_fromAssignmentRow).toList();
    } catch (e, st) {
      AppLogger.error('Workout.listAssignmentsByAthlete failed',
          error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> updateAssignmentStatus(
      String assignmentId, WorkoutAssignmentStatus status) async {
    try {
      await _db
          .from('coaching_workout_assignments')
          .update({
            'status': assignmentStatusToString(status),
          })
          .eq('id', assignmentId);
    } catch (e, st) {
      AppLogger.error('Workout.updateAssignmentStatus failed',
          error: e, stack: st);
      rethrow;
    }
  }

  // ── Mappers ──

  static WorkoutTemplateEntity _fromTemplateRow(
    Map<String, dynamic> r, {
    List<WorkoutBlockEntity> blocks = const [],
  }) =>
      WorkoutTemplateEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        createdBy: r['created_by'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        blocks: blocks,
      );

  static WorkoutBlockEntity _fromBlockRow(Map<String, dynamic> r) {
    final legacyPace = r['target_pace_seconds_per_km'] as int?;
    return WorkoutBlockEntity(
      id: r['id'] as String,
      templateId: r['template_id'] as String,
      orderIndex: r['order_index'] as int,
      blockType: workoutBlockTypeFromString(r['block_type'] as String),
      durationSeconds: r['duration_seconds'] as int?,
      distanceMeters: r['distance_meters'] as int?,
      targetPaceMinSecPerKm:
          r['target_pace_min_sec_per_km'] as int? ?? legacyPace,
      targetPaceMaxSecPerKm:
          r['target_pace_max_sec_per_km'] as int? ?? legacyPace,
      targetHrZone: r['target_hr_zone'] as int?,
      targetHrMin: r['target_hr_min'] as int?,
      targetHrMax: r['target_hr_max'] as int?,
      rpeTarget: r['rpe_target'] as int?,
      repeatCount: r['repeat_count'] as int?,
      notes: r['notes'] as String?,
    );
  }

  static WorkoutAssignmentEntity _fromAssignmentRow(
          Map<String, dynamic> r) =>
      WorkoutAssignmentEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        athleteUserId: r['athlete_user_id'] as String,
        templateId: r['template_id'] as String,
        scheduledDate: DateTime.parse(r['scheduled_date'] as String),
        status: assignmentStatusFromString(r['status'] as String),
        version: r['version'] as int? ?? 1,
        notes: r['notes'] as String?,
        createdBy: r['created_by'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        templateName:
            (r['coaching_workout_templates'] as Map<String, dynamic>?)?['name']
                as String?,
        athleteDisplayName:
            (r['profiles'] as Map<String, dynamic>?)?['display_name']
                as String?,
      );
}
