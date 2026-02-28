import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';

class VerificationBloc extends Bloc<VerificationEvent, VerificationState> {
  static const _tag = 'VerificationBloc';

  VerificationBloc() : super(const VerificationInitial()) {
    on<LoadVerificationState>(_onLoad);
    on<RequestEvaluation>(_onEvaluate);
  }

  AthleteVerificationEntity? _cached;

  AthleteVerificationEntity? get cached => _cached;

  Future<void> _onLoad(
    LoadVerificationState event,
    Emitter<VerificationState> emit,
  ) async {
    emit(const VerificationLoading());
    try {
      await _backfillStravaIfConnected();
      final entity = await _fetchState();
      _cached = entity;
      emit(VerificationLoaded(entity));
    } on Exception catch (e) {
      AppLogger.warn('Failed to load verification state: $e', tag: _tag);
      emit(const VerificationError(
        'Não foi possível carregar o status de verificação.',
      ));
    }
  }

  Future<void> _onEvaluate(
    RequestEvaluation event,
    Emitter<VerificationState> emit,
  ) async {
    emit(VerificationEvaluating(previous: _cached));
    try {
      if (!AppConfig.isSupabaseReady) {
        emit(const VerificationError('Sem conexão com o servidor.'));
        return;
      }

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        emit(const VerificationError('Usuário não autenticado.'));
        return;
      }

      // 1. Backfill Strava history → sessions
      await _backfillStravaIfConnected();

      // 2. Run evaluation RPC directly (more reliable than Edge Function)
      await Supabase.instance.client
          .rpc('eval_athlete_verification', params: {'p_user_id': uid});

      // 3. Re-read the updated state
      final entity = await _fetchState();
      _cached = entity;
      emit(VerificationLoaded(entity));
    } on Exception catch (e) {
      AppLogger.warn('Evaluation failed: $e', tag: _tag);
      emit(VerificationError(
        'Falha na avaliação: $e',
      ));
    }
  }

  /// If Strava is connected, backfill history into sessions so they
  /// count for verification. Non-blocking on failure.
  Future<void> _backfillStravaIfConnected() async {
    try {
      final controller = sl<StravaConnectController>();
      final connected = await controller.isConnected;
      if (!connected) return;

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final result = await Supabase.instance.client
          .rpc('backfill_strava_sessions', params: {'p_user_id': uid});
      final count = result as int? ?? 0;
      if (count > 0) {
        AppLogger.info('Backfilled $count Strava sessions', tag: _tag);
      }
    } on Exception catch (e) {
      AppLogger.warn('Strava backfill skipped: $e', tag: _tag);
    }
  }

  Future<AthleteVerificationEntity> _fetchState() async {
    if (!AppConfig.isSupabaseReady) {
      throw Exception('Supabase not ready');
    }

    final res = await Supabase.instance.client
        .rpc('get_verification_state')
        .single();

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
