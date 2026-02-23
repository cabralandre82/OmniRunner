import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_state.dart';

class CoachingRankingsBloc
    extends Bloc<CoachingRankingsEvent, CoachingRankingsState> {
  final ICoachingRankingRepo _rankingRepo;

  String _groupId = '';
  CoachingRankingMetric _metric = CoachingRankingMetric.volumeDistance;
  CoachingRankingPeriod _period = CoachingRankingPeriod.weekly;
  String _periodKey = '';

  CoachingRankingsBloc({
    required ICoachingRankingRepo rankingRepo,
  })  : _rankingRepo = rankingRepo,
        super(const CoachingRankingsInitial()) {
    on<LoadCoachingRanking>(_onLoad);
    on<ChangeMetricFilter>(_onChangeMetric);
    on<ChangePeriodFilter>(_onChangePeriod);
    on<RefreshCoachingRanking>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadCoachingRanking event,
    Emitter<CoachingRankingsState> emit,
  ) async {
    _groupId = event.groupId;
    _metric = event.metric;
    _period = event.period;
    _periodKey = event.periodKey;
    await _fetch(emit);
  }

  Future<void> _onChangeMetric(
    ChangeMetricFilter event,
    Emitter<CoachingRankingsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    _metric = event.metric;
    await _fetch(emit);
  }

  Future<void> _onChangePeriod(
    ChangePeriodFilter event,
    Emitter<CoachingRankingsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    _period = event.period;
    _periodKey = event.periodKey;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshCoachingRanking event,
    Emitter<CoachingRankingsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<CoachingRankingsState> emit) async {
    emit(CoachingRankingsLoading(metric: _metric, period: _period));
    try {
      final ranking = await _rankingRepo.getByGroupMetricPeriod(
        _groupId,
        _metric,
        _periodKey,
      );

      if (ranking == null || ranking.entries.isEmpty) {
        emit(CoachingRankingsEmpty(
          selectedMetric: _metric,
          selectedPeriod: _period,
        ));
        return;
      }

      emit(CoachingRankingsLoaded(
        ranking: ranking,
        selectedMetric: _metric,
        selectedPeriod: _period,
      ));
    } on Exception catch (e) {
      emit(CoachingRankingsError('Erro ao carregar ranking: $e'));
    }
  }
}
