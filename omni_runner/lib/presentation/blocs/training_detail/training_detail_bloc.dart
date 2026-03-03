import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/repositories/i_training_session_repo.dart';
import 'package:omni_runner/domain/usecases/training/cancel_training_session.dart';
import 'package:omni_runner/domain/usecases/training/list_attendance.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_event.dart';
import 'package:omni_runner/presentation/blocs/training_detail/training_detail_state.dart';

class TrainingDetailBloc extends Bloc<TrainingDetailEvent, TrainingDetailState> {
  final ITrainingSessionRepo _sessionRepo;
  final ListAttendance _listAttendance;
  final CancelTrainingSession _cancelTrainingSession;

  String _sessionId = '';

  TrainingDetailBloc({
    required ITrainingSessionRepo sessionRepo,
    required ListAttendance listAttendance,
    required CancelTrainingSession cancelTrainingSession,
  })  : _sessionRepo = sessionRepo,
        _listAttendance = listAttendance,
        _cancelTrainingSession = cancelTrainingSession,
        super(const TrainingDetailInitial()) {
    on<LoadTrainingDetail>(_onLoad);
    on<RefreshTrainingDetail>(_onRefresh);
    on<CancelTraining>(_onCancel);
    on<AttendanceMarked>(_onAttendanceMarked);
  }

  Future<void> _onLoad(
    LoadTrainingDetail event,
    Emitter<TrainingDetailState> emit,
  ) async {
    _sessionId = event.sessionId;
    emit(const TrainingDetailLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshTrainingDetail event,
    Emitter<TrainingDetailState> emit,
  ) async {
    if (_sessionId.isEmpty) return;
    emit(const TrainingDetailLoading());
    await _fetch(emit);
  }

  Future<void> _onCancel(
    CancelTraining event,
    Emitter<TrainingDetailState> emit,
  ) async {
    if (_sessionId.isEmpty) return;
    try {
      await _cancelTrainingSession.call(sessionId: _sessionId);
      await _fetch(emit);
    } catch (e) {
      emit(TrainingDetailError('Erro ao cancelar treino: $e'));
    }
  }

  Future<void> _onAttendanceMarked(
    AttendanceMarked event,
    Emitter<TrainingDetailState> emit,
  ) async {
    if (_sessionId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<TrainingDetailState> emit) async {
    try {
      final session = await _sessionRepo.getById(_sessionId);
      if (session == null) {
        emit(const TrainingDetailError('Sessão não encontrada'));
        return;
      }
      final attendance = await _listAttendance.bySession(_sessionId);
      emit(TrainingDetailLoaded(
        session: session,
        attendance: attendance,
        attendanceCount: attendance.length,
      ));
    } catch (e) {
      emit(TrainingDetailError('Erro ao carregar detalhe do treino: $e'));
    }
  }
}
