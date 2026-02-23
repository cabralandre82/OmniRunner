import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_state.dart';

class GroupEvolutionBloc
    extends Bloc<GroupEvolutionEvent, GroupEvolutionState> {
  final IAthleteTrendRepo _trendRepo;

  String _groupId = '';
  TrendDirection? _directionFilter;

  GroupEvolutionBloc({
    required IAthleteTrendRepo trendRepo,
  })  : _trendRepo = trendRepo,
        super(const GroupEvolutionInitial()) {
    on<LoadGroupEvolution>(_onLoad);
    on<ChangeDirectionFilter>(_onChangeDirection);
    on<RefreshGroupEvolution>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadGroupEvolution event,
    Emitter<GroupEvolutionState> emit,
  ) async {
    _groupId = event.groupId;
    _directionFilter = event.directionFilter;
    await _fetch(emit);
  }

  Future<void> _onChangeDirection(
    ChangeDirectionFilter event,
    Emitter<GroupEvolutionState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    _directionFilter = event.direction;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshGroupEvolution event,
    Emitter<GroupEvolutionState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<GroupEvolutionState> emit) async {
    emit(GroupEvolutionLoading(directionFilter: _directionFilter));
    try {
      final allTrends = await _trendRepo.getByGroup(_groupId);

      if (allTrends.isEmpty) {
        emit(GroupEvolutionEmpty(directionFilter: _directionFilter));
        return;
      }

      final improvingCount = allTrends
          .where((t) => t.direction == TrendDirection.improving)
          .length;
      final stableCount = allTrends
          .where((t) => t.direction == TrendDirection.stable)
          .length;
      final decliningCount = allTrends
          .where((t) => t.direction == TrendDirection.declining)
          .length;
      final insufficientCount = allTrends
          .where((t) => t.direction == TrendDirection.insufficient)
          .length;

      final filtered = _directionFilter != null
          ? allTrends.where((t) => t.direction == _directionFilter).toList()
          : allTrends;

      emit(GroupEvolutionLoaded(
        trends: filtered,
        directionFilter: _directionFilter,
        improvingCount: improvingCount,
        stableCount: stableCount,
        decliningCount: decliningCount,
        insufficientCount: insufficientCount,
      ));
    } on Exception catch (e) {
      emit(GroupEvolutionError('Erro ao carregar evolução do grupo: $e'));
    }
  }
}
