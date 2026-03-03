import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/usecases/training/list_training_sessions.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_event.dart';
import 'package:omni_runner/presentation/blocs/training_list/training_list_state.dart';

class TrainingListBloc extends Bloc<TrainingListEvent, TrainingListState> {
  final ListTrainingSessions _listSessions;

  String? _groupId;
  DateTime? _from;
  DateTime? _to;

  TrainingListBloc({
    required ListTrainingSessions listSessions,
  })  : _listSessions = listSessions,
        super(const TrainingListInitial()) {
    on<LoadTrainingSessions>(_onLoad);
    on<RefreshTrainingSessions>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadTrainingSessions event,
    Emitter<TrainingListState> emit,
  ) async {
    _groupId = event.groupId;
    _from = event.from;
    _to = event.to;
    emit(const TrainingListLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshTrainingSessions event,
    Emitter<TrainingListState> emit,
  ) async {
    if (_groupId == null) return;
    emit(const TrainingListLoading());
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<TrainingListState> emit) async {
    try {
      final sessions = await _listSessions.call(
        groupId: _groupId!,
        from: _from,
        to: _to,
      );
      emit(TrainingListLoaded(sessions: sessions));
    } catch (e, st) {
      AppLogger.error('Failed to load trainings', tag: 'TrainingListBloc', error: e, stack: st);
      emit(TrainingListError('Erro ao carregar treinos: $e'));
    }
  }
}
