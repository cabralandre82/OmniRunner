import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/core/logging/logger.dart' show AppLogger;
import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';

/// Supabase-backed implementation that calls `fn_switch_assessoria` RPC.
///
/// The RPC burns remaining coins, updates `active_coaching_group_id`,
/// and manages coaching_members entries atomically.
final class RemoteSwitchAssessoriaRepo implements ISwitchAssessoriaRepo {
  static const _tag = 'RemoteSwitchAssessoria';

  SupabaseClient get _client => Supabase.instance.client;

  const RemoteSwitchAssessoriaRepo();

  @override
  Future<String> switchTo(String newGroupId) async {
    try {
      final result = await _client.rpc(
        'fn_switch_assessoria',
        params: {'p_new_group_id': newGroupId},
      );

      AppLogger.info('Switch assessoria result: $result', tag: _tag);
      return newGroupId;
    } on PostgrestException catch (e) {
      AppLogger.error('RPC error: ${e.message}', tag: _tag);
      throw SwitchAssessoriaFailed(newGroupId, e.message);
    } on AuthException catch (e) {
      AppLogger.error('Auth error: ${e.message}', tag: _tag);
      throw SwitchAssessoriaFailed(newGroupId, e.message);
    }
  }
}
