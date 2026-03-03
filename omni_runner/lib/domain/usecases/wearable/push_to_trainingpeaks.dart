import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';

class PushToTrainingPeaks {
  final SupabaseClient _db;

  const PushToTrainingPeaks(this._db);

  Future<Map<String, dynamic>> call(String assignmentId) async {
    try {
      final res = await _db.rpc('fn_push_to_trainingpeaks', params: {
        'p_assignment_id': assignmentId,
      });
      return res as Map<String, dynamic>;
    } catch (e, st) {
      AppLogger.error('PushToTrainingPeaks failed', error: e, stack: st);
      rethrow;
    }
  }
}
