import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/domain/repositories/i_verification_remote_source.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';

class SupabaseVerificationRemoteSource implements IVerificationRemoteSource {
  static const _tag = 'VerifRemoteSource';

  /// Factory that returns a fresh [StravaConnectController] on each call,
  /// matching the original behaviour where the BLoC called
  /// `sl<StravaConnectController>()` every time.
  final StravaConnectController Function() _stravaFactory;

  SupabaseVerificationRemoteSource({
    required StravaConnectController Function() stravaFactory,
  }) : _stravaFactory = stravaFactory;

  SupabaseClient get _client => sl<SupabaseClient>();

  @override
  bool get isBackendReady => AppConfig.isSupabaseReady;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> backfillStravaIfConnected() async {
    try {
      final controller = _stravaFactory();
      final connected = await controller.isConnected;
      if (!connected) return;

      final uid = currentUserId;
      if (uid == null) return;

      try {
        await controller.importStravaHistory(count: 30);
      } catch (e) {
        AppLogger.warn('Strava import skipped: $e', tag: _tag);
      }

      await _client
          .rpc('backfill_strava_sessions', params: {'p_user_id': uid});
      await _client
          .rpc('backfill_park_activities', params: {'p_user_id': uid});
      await _client
          .rpc('recalculate_profile_progress', params: {'p_user_id': uid});

      AppLogger.info('Strava + park + profile backfill completed', tag: _tag);
    } catch (e) {
      AppLogger.warn('Strava backfill skipped: $e', tag: _tag);
    }
  }

  @override
  Future<void> evaluateMyVerification() async {
    await _client.rpc('eval_my_verification');
  }

  @override
  Future<AthleteVerificationEntity> fetchVerificationState() async {
    if (!isBackendReady) throw Exception('Supabase not ready');

    final res = await _client.rpc('get_verification_state').single();
    return _parseRpcRow(res);
  }

  static AthleteVerificationEntity _parseRpcRow(Map<String, dynamic> r) {
    return AthleteVerificationEntity(
      status: AthleteVerificationEntity.parseStatus(
        r['verification_status'] as String?,
      ),
      trustScore: (r['trust_score'] as num?)?.toInt() ?? 0,
      verifiedAt: _tryParseDate(r['verified_at']),
      lastEvalAt: _tryParseDate(r['last_eval_at']),
      verificationFlags:
          (r['verification_flags'] as List<dynamic>?)?.cast<String>() ??
              const [],
      calibrationValidRuns:
          (r['calibration_valid_runs'] as num?)?.toInt() ?? 0,
      identityOk: r['identity_ok'] as bool?,
      permissionsOk: r['permissions_ok'] as bool?,
      validRunsOk: (r['valid_runs_ok'] as bool?) ?? false,
      integrityOk: (r['integrity_ok'] as bool?) ?? false,
      baselineOk: (r['baseline_ok'] as bool?) ?? false,
      trustOk: (r['trust_ok'] as bool?) ?? false,
      validRunsCount: (r['valid_runs_count'] as num?)?.toInt() ?? 0,
      flaggedRunsRecent: (r['flagged_runs_recent'] as num?)?.toInt() ?? 0,
      totalDistanceM: (r['total_distance_m'] as num?)?.toDouble() ?? 0,
      avgDistanceM: (r['avg_distance_m'] as num?)?.toDouble() ?? 0,
      requiredValidRuns: (r['required_valid_runs'] as num?)?.toInt() ?? 7,
      requiredTrustScore: (r['required_trust_score'] as num?)?.toInt() ?? 80,
    );
  }

  static DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
