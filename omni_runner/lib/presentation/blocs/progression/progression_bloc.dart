import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';

class ProgressionBloc extends Bloc<ProgressionEvent, ProgressionState> {
  final IProfileProgressRepo _profileRepo;
  final IXpTransactionRepo _xpRepo;

  String _userId = '';

  ProgressionBloc({
    required IProfileProgressRepo profileRepo,
    required IXpTransactionRepo xpRepo,
  })  : _profileRepo = profileRepo,
        _xpRepo = xpRepo,
        super(const ProgressionInitial()) {
    on<LoadProgression>(_onLoad);
    on<RefreshProgression>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    _userId = event.userId;
    emit(const ProgressionLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<ProgressionState> emit) async {
    try {
      final profile = await _profileRepo.getByUserId(_userId);
      final xpHistory = await _xpRepo.getByUserId(_userId);
      final weeklyGoal = await _fetchWeeklyGoal();
      emit(ProgressionLoaded(
        profile: profile,
        recentXp: xpHistory,
        weeklyGoal: weeklyGoal,
      ));
    } on Exception catch (e) {
      emit(ProgressionError('Erro ao carregar progressão: $e'));
    }
  }

  Future<WeeklyGoalEntity?> _fetchWeeklyGoal() async {
    try {
      final db = Supabase.instance.client;
      final now = DateTime.now().toUtc();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      final rows = await db
          .from('weekly_goals')
          .select()
          .eq('user_id', _userId)
          .eq('week_start', weekStartDate)
          .limit(1);

      if (rows.isEmpty) return null;
      final r = rows.first;
      return WeeklyGoalEntity(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        weekStart: DateTime.parse(r['week_start'] as String),
        metric: (r['metric'] as String) == 'time'
            ? GoalMetric.time
            : GoalMetric.distance,
        targetValue: (r['target_value'] as num).toDouble(),
        currentValue: (r['current_value'] as num).toDouble(),
        status: _parseStatus(r['status'] as String),
        xpAwarded: (r['xp_awarded'] as num?)?.toInt() ?? 0,
        completedAt: r['completed_at'] != null
            ? DateTime.tryParse(r['completed_at'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  static GoalStatus _parseStatus(String s) => switch (s) {
        'completed' => GoalStatus.completed,
        'missed' => GoalStatus.missed,
        _ => GoalStatus.active,
      };
}
