import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_state.dart';

class AthleteEvolutionBloc
    extends Bloc<AthleteEvolutionEvent, AthleteEvolutionState> {
  final IAthleteTrendRepo _trendRepo;
  final IAthleteBaselineRepo _baselineRepo;

  String _userId = '';
  String _groupId = '';
  EvolutionMetric _metric = EvolutionMetric.avgPace;
  EvolutionPeriod _period = EvolutionPeriod.weekly;

  AthleteEvolutionBloc({
    required IAthleteTrendRepo trendRepo,
    required IAthleteBaselineRepo baselineRepo,
  })  : _trendRepo = trendRepo,
        _baselineRepo = baselineRepo,
        super(const AthleteEvolutionInitial()) {
    on<LoadAthleteEvolution>(_onLoad);
    on<ChangeEvolutionMetric>(_onChangeMetric);
    on<ChangeEvolutionPeriod>(_onChangePeriod);
    on<RefreshAthleteEvolution>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadAthleteEvolution event,
    Emitter<AthleteEvolutionState> emit,
  ) async {
    _userId = event.userId;
    _groupId = event.groupId;
    _metric = event.metric;
    _period = event.period;
    await _fetch(emit);
  }

  Future<void> _onChangeMetric(
    ChangeEvolutionMetric event,
    Emitter<AthleteEvolutionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    _metric = event.metric;
    await _fetch(emit);
  }

  Future<void> _onChangePeriod(
    ChangeEvolutionPeriod event,
    Emitter<AthleteEvolutionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    _period = event.period;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshAthleteEvolution event,
    Emitter<AthleteEvolutionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<AthleteEvolutionState> emit) async {
    emit(AthleteEvolutionLoading(metric: _metric, period: _period));
    try {
      final trends = await _trendRepo.getByUserAndGroup(
        userId: _userId,
        groupId: _groupId,
      );
      final baselines = await _baselineRepo.getByUserAndGroup(
        userId: _userId,
        groupId: _groupId,
      );

      if (trends.isEmpty && baselines.isEmpty) {
        emit(AthleteEvolutionEmpty(metric: _metric, period: _period));
        return;
      }

      final selectedTrend = await _trendRepo.getByUserGroupMetricPeriod(
        userId: _userId,
        groupId: _groupId,
        metric: _metric,
        period: _period,
      );
      final selectedBaseline = await _baselineRepo.getByUserGroupMetric(
        userId: _userId,
        groupId: _groupId,
        metric: _metric,
      );

      emit(AthleteEvolutionLoaded(
        trends: trends,
        baselines: baselines,
        selectedMetric: _metric,
        selectedPeriod: _period,
        selectedTrend: selectedTrend,
        selectedBaseline: selectedBaseline,
      ));
    } on Exception catch (e) {
      emit(AthleteEvolutionError('Erro ao carregar evolução: $e'));
    }
  }
}
