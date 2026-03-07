import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/repositories/i_trainingpeaks_repo.dart';

class SupabaseTrainingPeaksRepo implements ITrainingPeaksRepo {
  final SupabaseClient _client;

  const SupabaseTrainingPeaksRepo(this._client);

  @override
  Future<Map<String, dynamic>> pushAssignment(String assignmentId) async {
    try {
      final res = await _client.rpc('fn_push_to_trainingpeaks', params: {
        'p_assignment_id': assignmentId,
      });
      return res as Map<String, dynamic>;
    } catch (e, st) {
      AppLogger.error('PushToTrainingPeaks failed', error: e, stack: st);
      rethrow;
    }
  }
}
