import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_training_attendance_repo.dart';
import 'package:omni_runner/domain/usecases/training/issue_checkin_token.dart';
import 'package:omni_runner/domain/usecases/training/mark_attendance.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_event.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_state.dart';

class CheckinBloc extends Bloc<CheckinEvent, CheckinState> {
  final IssueCheckinToken _issueToken;
  final MarkAttendance _markAttendance;

  CheckinBloc({
    required IssueCheckinToken issueToken,
    required MarkAttendance markAttendance,
  })  : _issueToken = issueToken,
        _markAttendance = markAttendance,
        super(const CheckinInitial()) {
    on<GenerateCheckinQr>(_onGenerateCheckinQr);
    on<ConsumeCheckinQr>(_onConsumeCheckinQr);
    on<ResetCheckin>(_onResetCheckin);
  }

  Future<void> _onGenerateCheckinQr(
    GenerateCheckinQr event,
    Emitter<CheckinState> emit,
  ) async {
    emit(const CheckinGenerating());
    try {
      final token = await _issueToken.call(sessionId: event.sessionId);
      final payload = {
        'sid': token.sessionId,
        'uid': token.athleteUserId,
        'gid': token.groupId,
        'non': token.nonce,
        'exp': token.expiresAtMs,
      };
      final encodedPayload = base64Url.encode(
        utf8.encode(json.encode(payload)),
      );
      emit(CheckinQrReady(token: token, encodedPayload: encodedPayload));
    } on Object catch (e) {
      emit(CheckinError('Erro ao gerar QR: $e'));
    }
  }

  Future<void> _onConsumeCheckinQr(
    ConsumeCheckinQr event,
    Emitter<CheckinState> emit,
  ) async {
    emit(const CheckinConsuming());
    try {
      final decoded = utf8.decode(base64Url.decode(event.rawPayload));
      final payload = json.decode(decoded) as Map<String, dynamic>;
      final sessionId = payload['sid'] as String?;
      final athleteUserId = payload['uid'] as String?;
      final nonce = payload['non'] as String?;
      final expiresAtMs = payload['exp'] as int?;

      if (sessionId == null ||
          athleteUserId == null ||
          sessionId.isEmpty ||
          athleteUserId.isEmpty) {
        emit(const CheckinError('Payload inválido'));
        return;
      }

      final token = CheckinToken(
        sessionId: sessionId,
        athleteUserId: athleteUserId,
        groupId: payload['gid'] as String? ?? '',
        nonce: nonce ?? '',
        expiresAtMs: expiresAtMs ?? 0,
      );

      if (token.isExpired) {
        emit(const CheckinError('QR expirado'));
        return;
      }

      final result = await _markAttendance.call(
        sessionId: sessionId,
        athleteUserId: athleteUserId,
        nonce: nonce,
      );

      switch (result) {
        case AttendanceInserted():
          emit(const CheckinSuccess(status: 'inserted'));
        case AttendanceAlreadyPresent():
          emit(const CheckinSuccess(status: 'already_present'));
        case AttendanceFailed(:final message):
          emit(CheckinError(message));
      }
    } on Object catch (e) {
      emit(CheckinError('Erro ao processar check-in: $e'));
    }
  }

  void _onResetCheckin(
    ResetCheckin event,
    Emitter<CheckinState> emit,
  ) {
    emit(const CheckinInitial());
  }
}
