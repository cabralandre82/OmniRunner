import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/repositories/i_training_plan_repo.dart';
import 'package:omni_runner/data/services/training_sync_service.dart';

import 'training_feed_event.dart';
import 'training_feed_state.dart';

class TrainingFeedBloc extends Bloc<TrainingFeedEvent, TrainingFeedState> {
  TrainingFeedBloc({
    required ITrainingPlanRepo repo,
    required TrainingSyncService syncService,
  })  : _repo = repo,
        _syncService = syncService,
        super(const TrainingFeedInitial()) {
    on<LoadTrainingFeed>(_onLoad);
    on<RefreshTrainingFeed>(_onRefresh);
    on<SyncTrainingFeed>(_onSync);
    on<SelectFeedDate>(_onSelectDate);
  }

  final ITrainingPlanRepo _repo;
  final TrainingSyncService _syncService;

  static const _tag = 'TrainingFeedBloc';

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _onLoad(
    LoadTrainingFeed event,
    Emitter<TrainingFeedState> emit,
  ) async {
    emit(const TrainingFeedLoading());
    try {
      final today = event.focusDate ?? DateTime.now();
      final from  = today.subtract(const Duration(days: 7));
      final to    = today.add(const Duration(days: 21));

      final workouts = await _repo.getWorkoutsForPeriod(from: from, to: to);
      final byDate   = _groupByDate(workouts);

      emit(TrainingFeedLoaded(
        workoutsByDate: byDate,
        selectedDate:   today,
      ));

      // Kick off background sync after initial load
      add(const SyncTrainingFeed());
    } on Object catch (e, stack) {
      AppLogger.error('LoadTrainingFeed failed', tag: _tag, error: e, stack: stack);
      emit(TrainingFeedError(e.toString()));
    }
  }

  // ── Refresh (pull-to-refresh) ─────────────────────────────────────────────

  Future<void> _onRefresh(
    RefreshTrainingFeed event,
    Emitter<TrainingFeedState> emit,
  ) async {
    final current = state;
    if (current is TrainingFeedLoaded) {
      emit(current.copyWith(isSyncing: true));
    }
    try {
      final today    = state is TrainingFeedLoaded
          ? (state as TrainingFeedLoaded).selectedDate
          : DateTime.now();
      final from     = today.subtract(const Duration(days: 7));
      final to       = today.add(const Duration(days: 21));

      final workouts = await _repo.getWorkoutsForPeriod(from: from, to: to);
      final byDate   = _groupByDate(workouts);

      if (state is TrainingFeedLoaded) {
        emit((state as TrainingFeedLoaded).copyWith(
          workoutsByDate: byDate,
          isSyncing: false,
          lastSyncAt: DateTime.now(),
        ));
      } else {
        emit(TrainingFeedLoaded(
          workoutsByDate: byDate,
          selectedDate:   today,
          lastSyncAt:     DateTime.now(),
        ));
      }
    } on Object catch (e, stack) {
      AppLogger.error('RefreshTrainingFeed failed', tag: _tag, error: e, stack: stack);
      if (state is TrainingFeedLoaded) {
        emit((state as TrainingFeedLoaded).copyWith(isSyncing: false));
      }
    }
  }

  // ── Background sync (cursor-based) ───────────────────────────────────────

  Future<void> _onSync(
    SyncTrainingFeed event,
    Emitter<TrainingFeedState> emit,
  ) async {
    try {
      final delta = await _syncService.syncDelta();
      if (delta.isEmpty) return;
      if (state is! TrainingFeedLoaded) return;

      final current = state as TrainingFeedLoaded;
      final updated = Map<String, List<PlanWorkoutEntity>>.from(current.workoutsByDate);

      for (final workout in delta) {
        final key = _dateKeyFrom(workout.scheduledDate);
        final existing = List<PlanWorkoutEntity>.from(updated[key] ?? []);
        final idx = existing.indexWhere((w) => w.id == workout.id);
        if (idx >= 0) {
          existing[idx] = workout;
        } else {
          existing.add(workout);
          existing.sort((a, b) => a.workoutOrder.compareTo(b.workoutOrder));
        }
        updated[key] = existing;
      }

      emit(current.copyWith(
        workoutsByDate: updated,
        lastSyncAt:     DateTime.now(),
      ));
    } on Object catch (e) {
      AppLogger.debug('Background sync failed silently', tag: _tag, error: e);
    }
  }

  // ── Select date ───────────────────────────────────────────────────────────

  Future<void> _onSelectDate(
    SelectFeedDate event,
    Emitter<TrainingFeedState> emit,
  ) async {
    if (state is TrainingFeedLoaded) {
      emit((state as TrainingFeedLoaded).copyWith(selectedDate: event.date));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Map<String, List<PlanWorkoutEntity>> _groupByDate(
    List<PlanWorkoutEntity> workouts,
  ) {
    final map = <String, List<PlanWorkoutEntity>>{};
    for (final w in workouts) {
      final key = _dateKeyFrom(w.scheduledDate);
      map.putIfAbsent(key, () => []).add(w);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.workoutOrder.compareTo(b.workoutOrder));
    }
    return map;
  }

  static String _dateKeyFrom(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
      '${d.month.toString().padLeft(2,'0')}-'
      '${d.day.toString().padLeft(2,'0')}';
}
