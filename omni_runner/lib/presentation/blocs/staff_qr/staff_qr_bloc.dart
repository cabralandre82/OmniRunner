import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';

class StaffQrBloc extends Bloc<StaffQrEvent, StaffQrState> {
  final ITokenIntentRepo _repo;

  StaffQrBloc({required ITokenIntentRepo repo})
      : _repo = repo,
        super(const StaffQrInitial()) {
    on<GenerateQr>(_onGenerate);
    on<ConsumeScannedQr>(_onConsume);
    on<LoadEmissionCapacity>(_onLoadCapacity);
    on<LoadBadgeCapacity>(_onLoadBadgeCapacity);
    on<ResetStaffQr>(_onReset);
  }

  Future<void> _onGenerate(
    GenerateQr event,
    Emitter<StaffQrState> emit,
  ) async {
    emit(const StaffQrGenerating());
    try {
      final payload = await _repo.createIntent(
        type: event.type,
        groupId: event.groupId,
        amount: event.amount,
        championshipId: event.championshipId,
      );
      emit(StaffQrGenerated(payload));
    } on TokenIntentFailed catch (e) {
      emit(StaffQrError(e.reason));
    } on Exception catch (e) {
      emit(StaffQrError('Erro ao gerar QR: $e'));
    }
  }

  Future<void> _onConsume(
    ConsumeScannedQr event,
    Emitter<StaffQrState> emit,
  ) async {
    emit(const StaffQrConsuming());
    try {
      final payload = StaffQrPayload.decode(event.encodedPayload);
      if (payload.isExpired) {
        emit(const StaffQrError('QR expirado. Solicite um novo ao staff.'));
        return;
      }
      await _repo.consumeIntent(payload);
      emit(StaffQrConsumed(payload.type));
    } on TokenIntentFailed catch (e) {
      emit(StaffQrError(e.reason));
    } on FormatException {
      emit(const StaffQrError('QR inválido. Não é um token Omni Runner.'));
    } on Exception catch (e) {
      emit(StaffQrError('Erro ao processar QR: $e'));
    }
  }

  Future<void> _onLoadCapacity(
    LoadEmissionCapacity event,
    Emitter<StaffQrState> emit,
  ) async {
    try {
      final capacity = await _repo.getEmissionCapacity(event.groupId);
      emit(StaffQrCapacityLoaded(capacity));
    } on Exception catch (e) {
      emit(StaffQrError('Erro ao carregar capacidade: $e'));
    }
  }

  Future<void> _onLoadBadgeCapacity(
    LoadBadgeCapacity event,
    Emitter<StaffQrState> emit,
  ) async {
    try {
      final capacity = await _repo.getBadgeCapacity(event.groupId);
      emit(StaffQrBadgeCapacityLoaded(capacity));
    } on Exception catch (e) {
      emit(StaffQrError('Erro ao carregar badges: $e'));
    }
  }

  void _onReset(ResetStaffQr event, Emitter<StaffQrState> emit) {
    emit(const StaffQrInitial());
  }
}
