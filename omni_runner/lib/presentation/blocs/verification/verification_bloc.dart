import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';
import 'package:omni_runner/domain/repositories/i_verification_remote_source.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';

class VerificationBloc extends Bloc<VerificationEvent, VerificationState> {
  static const _tag = 'VerificationBloc';

  final IVerificationRemoteSource _remote;

  VerificationBloc({required IVerificationRemoteSource remote})
      : _remote = remote,
        super(const VerificationInitial()) {
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
      await _remote.backfillStravaIfConnected();
      final entity = await _remote.fetchVerificationState();
      _cached = entity;
      emit(VerificationLoaded(entity));
    } on Object catch (e) {
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
      if (!_remote.isBackendReady) {
        emit(const VerificationError('Sem conexão com o servidor.'));
        return;
      }

      if (_remote.currentUserId == null) {
        emit(const VerificationError('Usuário não autenticado.'));
        return;
      }

      await _remote.backfillStravaIfConnected();
      await _remote.evaluateMyVerification();

      final entity = await _remote.fetchVerificationState();
      _cached = entity;
      emit(VerificationLoaded(entity));
    } on Object catch (e) {
      AppLogger.warn('Evaluation failed: $e', tag: _tag);
      emit(VerificationError(
        'Falha na avaliação: $e',
      ));
    }
  }
}
