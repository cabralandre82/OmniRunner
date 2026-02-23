import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_event.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_state.dart';

class LeaderboardsBloc extends Bloc<LeaderboardsEvent, LeaderboardsState> {
  LeaderboardScope? _lastScope;
  LeaderboardPeriod? _lastPeriod;
  LeaderboardMetric? _lastMetric;
  String? _lastGroupId;
  String? _lastChampionshipId;

  LeaderboardsBloc() : super(const LeaderboardsInitial()) {
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

      final scopeStr = scope == LeaderboardScope.assessoria
          ? 'assessoria'
          : scope == LeaderboardScope.championship
              ? 'championship'
              : 'global';
      final periodStr = period == LeaderboardPeriod.monthly ? 'monthly' : 'weekly';

      final sb = Supabase.instance.client;

      // Build query to find matching leaderboard
      var query = sb
          .from('leaderboards')
          .select('id, scope, period, metric, period_key, computed_at_ms, is_final, coaching_group_id, championship_id')
          .eq('scope', scopeStr)
          .eq('period', periodStr);

      if (scope == LeaderboardScope.assessoria && _lastGroupId != null) {
        query = query.eq('coaching_group_id', _lastGroupId!);
      } else if (scope == LeaderboardScope.championship &&
          _lastChampionshipId != null) {
        query = query.eq('championship_id', _lastChampionshipId!);
      }

      final lbRows = await query
          .order('computed_at_ms', ascending: false)
          .limit(1);

      if (lbRows.isEmpty) {
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
        return;
      }

      final lb = lbRows.first;
      final lbId = lb['id'] as String;

      // Fetch entries
      final entryRows = await sb
          .from('leaderboard_entries')
          .select()
          .eq('leaderboard_id', lbId)
          .order('rank', ascending: true)
          .limit(200);

      final entries = entryRows.map((Map<String, dynamic> e) {
        return LeaderboardEntryEntity(
          userId: e['user_id'] as String,
          displayName: (e['display_name'] as String?) ?? 'Runner',
          avatarUrl: e['avatar_url'] as String?,
          level: (e['level'] as num?)?.toInt() ?? 0,
          value: (e['value'] as num?)?.toDouble() ?? 0,
          rank: (e['rank'] as num?)?.toInt() ?? 0,
          periodKey: (e['period_key'] as String?) ?? '',
        );
      }).toList();

      final lbMetricStr = (lb['metric'] as String?) ?? 'composite';
      final resolvedMetric = _parseMetric(lbMetricStr);

      emit(LeaderboardsLoaded(
        leaderboard: LeaderboardEntity(
          id: lbId,
          scope: scope,
          groupId: _lastGroupId,
          period: period,
          metric: resolvedMetric,
          periodKey: (lb['period_key'] as String?) ?? '',
          entries: entries,
          computedAtMs: (lb['computed_at_ms'] as num?)?.toInt() ?? 0,
          isFinal: (lb['is_final'] as bool?) ?? false,
        ),
      ));
    } on Exception catch (e) {
      emit(LeaderboardsError('Erro ao carregar ranking: $e'));
    }
  }

  static LeaderboardMetric _parseMetric(String s) => switch (s) {
        'distance' => LeaderboardMetric.distance,
        'sessions' => LeaderboardMetric.sessions,
        'moving_time' => LeaderboardMetric.movingTime,
        'avg_pace' => LeaderboardMetric.avgPace,
        'season_xp' => LeaderboardMetric.seasonXp,
        'pace' => LeaderboardMetric.avgPace,
        'time' => LeaderboardMetric.movingTime,
        _ => LeaderboardMetric.composite,
      };
}
