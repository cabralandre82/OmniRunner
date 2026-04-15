import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/presentation/blocs/workout_assignments/workout_assignments_event.dart';
import 'package:omni_runner/presentation/blocs/workout_assignments/workout_assignments_state.dart';

class WorkoutAssignmentsBloc
    extends Bloc<WorkoutAssignmentsEvent, WorkoutAssignmentsState> {
  final IWorkoutRepo _repo;

  String? _groupId;
  DateTime? _from;
  DateTime? _to;

  WorkoutAssignmentsBloc({required IWorkoutRepo repo})
      : _repo = repo,
        super(const AssignmentsInitial()) {
    on<LoadAssignments>(_onLoad);
    on<RefreshAssignments>(_onRefresh);
    on<AssignWorkout>(_onAssign);
  }

  Future<void> _onLoad(
    LoadAssignments event,
    Emitter<WorkoutAssignmentsState> emit,
  ) async {
    _groupId = event.groupId;
    _from = event.from;
    _to = event.to;
    emit(const AssignmentsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshAssignments event,
    Emitter<WorkoutAssignmentsState> emit,
  ) async {
    if (_groupId == null) return;
    emit(const AssignmentsLoading());
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<WorkoutAssignmentsState> emit) async {
    try {
      final assignments = await _repo.listAssignmentsByGroup(
        groupId: _groupId!,
        from: _from,
        to: _to,
      );
      emit(AssignmentsLoaded(assignments: assignments));
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao carregar atribuições',
        tag: 'WorkoutAssignmentsBloc',
        error: e,
        stack: stack,
      );
      emit(AssignmentsError('Erro ao carregar atribuições: $e'));
    }
  }

  Future<void> _onAssign(
    AssignWorkout event,
    Emitter<WorkoutAssignmentsState> emit,
  ) async {
    try {
      await _repo.assignWorkout(
        templateId: event.templateId,
        athleteUserId: event.athleteUserId,
        scheduledDate: event.date,
        notes: event.notes,
      );
      if (_groupId != null) {
        await _fetch(emit);
      }
    } on Object catch (e, stack) {
      AppLogger.error(
        'Erro ao atribuir treino',
        tag: 'WorkoutAssignmentsBloc',
        error: e,
        stack: stack,
      );
      emit(AssignmentsError('Erro ao atribuir treino: $e'));
    }
  }
}
