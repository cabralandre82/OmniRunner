import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/domain/repositories/i_leaderboard_repo.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_event.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_state.dart';

class LeaderboardsBloc extends Bloc<LeaderboardsEvent, LeaderboardsState> {
  final ILeaderboardRepo _repo;

  LeaderboardScope? _lastScope;
  LeaderboardPeriod? _lastPeriod;
  LeaderboardMetric? _lastMetric;
  String? _lastGroupId;
  String? _lastChampionshipId;

  LeaderboardsBloc({required ILeaderboardRepo repo})
      : _repo = repo,
        super(const LeaderboardsInitial()) {
    on<LoadLeaderboard>(_onLoad);
    on<RefreshLeaderboard>(_onRefresh);
  }

  Future<void> _onLoad(
      LoadLeaderboard event, Emitter<LeaderboardsState> emit) async {
    _lastScope = event.scope;
    _lastPeriod = event.period;
    _lastMetric = event.metric;
    _lastGroupId = event.groupId;
    _lastChampionshipId = event.championshipId;
    emit(const LeaderboardsLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
      RefreshLeaderboard event, Emitter<LeaderboardsState> emit) async {
    if (_lastScope == null) return;
    emit(const LeaderboardsLoading());
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<LeaderboardsState> emit) async {
    try {
      final scope = _lastScope!;
      final period = _lastPeriod ?? LeaderboardPeriod.weekly;
      final metric = _lastMetric ?? LeaderboardMetric.composite;

      final result = await _repo.fetchLeaderboard(
        scope: scope,
        period: period,
        metric: metric,
        groupId: _lastGroupId,
        championshipId: _lastChampionshipId,
      );

      if (result != null) {
        emit(LeaderboardsLoaded(leaderboard: result));
      } else {
        final scopeStr = switch (scope) {
          LeaderboardScope.assessoria => 'assessoria',
          LeaderboardScope.championship => 'championship',
          _ => 'global',
        };
        final periodStr =
            period == LeaderboardPeriod.monthly ? 'monthly' : 'weekly';

        emit(LeaderboardsLoaded(
          leaderboard: LeaderboardEntity(
            id: '${scopeStr}_${periodStr}_empty',
            scope: scope,
            groupId: _lastGroupId,
            period: period,
            metric: metric,
            periodKey: '',
            entries: const [],
            computedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ));
      }
    } on Exception catch (e) {
      emit(LeaderboardsError('Erro ao carregar ranking: $e'));
    }
  }
}
