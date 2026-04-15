import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/training_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';

final class SupabaseTrainingSessionRepo implements ITrainingSessionRepo {
  final SupabaseClient _db;

  const SupabaseTrainingSessionRepo(this._db);

  @override
  Future<TrainingSessionEntity> create(TrainingSessionEntity session) async {
    try {
      final row = await _db.from('coaching_training_sessions').insert({
        'id': session.id,
        'group_id': session.groupId,
        'created_by': session.createdBy,
        'title': session.title,
        'description': session.description,
        'starts_at': session.startsAt.toUtc().toIso8601String(),
        'ends_at': session.endsAt?.toUtc().toIso8601String(),
        'location_name': session.locationName,
        'location_lat': session.locationLat,
        'location_lng': session.locationLng,
        'distance_target_m': session.distanceTargetM,
        'pace_min_sec_km': session.paceMinSecKm,
        'pace_max_sec_km': session.paceMaxSecKm,
      }).select().single();
      return _fromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('TrainingSession.create failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<TrainingSessionEntity> update(TrainingSessionEntity session) async {
    try {
      final row = await _db
          .from('coaching_training_sessions')
          .update({
            'title': session.title,
            'description': session.description,
            'starts_at': session.startsAt.toUtc().toIso8601String(),
            'ends_at': session.endsAt?.toUtc().toIso8601String(),
            'location_name': session.locationName,
            'location_lat': session.locationLat,
            'location_lng': session.locationLng,
            'status': trainingStatusToString(session.status),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'distance_target_m': session.distanceTargetM,
            'pace_min_sec_km': session.paceMinSecKm,
            'pace_max_sec_km': session.paceMaxSecKm,
          })
          .eq('id', session.id)
          .select()
          .single();
      return _fromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('TrainingSession.update failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<TrainingSessionEntity?> getById(String id) async {
    try {
      final row = await _db
          .from('coaching_training_sessions')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : _fromRow(row);
    } on Object catch (e, st) {
      AppLogger.error('TrainingSession.getById failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<List<TrainingSessionEntity>> listByGroup({
    required String groupId,
    DateTime? from,
    DateTime? to,
    TrainingSessionStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _db
          .from('coaching_training_sessions')
          .select()
          .eq('group_id', groupId);

      if (from != null) {
        query = query.gte('starts_at', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lte('starts_at', to.toUtc().toIso8601String());
      }
      if (status != null) {
        query = query.eq('status', trainingStatusToString(status));
      }

      final rows = await query
          .order('starts_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map(_fromRow).toList();
    } on Object catch (e, st) {
      AppLogger.error('TrainingSession.listByGroup failed', error: e, stack: st);
      rethrow;
    }
  }

  @override
  Future<void> cancel(String sessionId) async {
    try {
      await _db
          .from('coaching_training_sessions')
          .update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sessionId);
    } on Object catch (e, st) {
      AppLogger.error('TrainingSession.cancel failed', error: e, stack: st);
      rethrow;
    }
  }

  static TrainingSessionEntity _fromRow(Map<String, dynamic> r) =>
      TrainingSessionEntity(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        createdBy: r['created_by'] as String,
        title: r['title'] as String,
        description: r['description'] as String?,
        startsAt: DateTime.parse(r['starts_at'] as String),
        endsAt: r['ends_at'] != null
            ? DateTime.parse(r['ends_at'] as String)
            : null,
        locationName: r['location_name'] as String?,
        locationLat: (r['location_lat'] as num?)?.toDouble(),
        locationLng: (r['location_lng'] as num?)?.toDouble(),
        status: trainingStatusFromString(r['status'] as String),
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        distanceTargetM: (r['distance_target_m'] as num?)?.toDouble(),
        paceMinSecKm: (r['pace_min_sec_km'] as num?)?.toDouble(),
        paceMaxSecKm: (r['pace_max_sec_km'] as num?)?.toDouble(),
      );
}
