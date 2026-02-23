import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';
import 'package:omni_runner/domain/repositories/i_coach_insight_repo.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_event.dart';
import 'package:omni_runner/presentation/blocs/coach_insights/coach_insights_state.dart';

class CoachInsightsBloc
    extends Bloc<CoachInsightsEvent, CoachInsightsState> {
  final ICoachInsightRepo _repo;

  String _groupId = '';
  InsightType? _typeFilter;
  bool _unreadOnly = false;

  CoachInsightsBloc({required ICoachInsightRepo repo})
      : _repo = repo,
        super(const CoachInsightsInitial()) {
    on<LoadCoachInsights>(_onLoad);
    on<RefreshCoachInsights>(_onRefresh);
    on<FilterByType>(_onFilterByType);
    on<FilterUnreadOnly>(_onFilterUnread);
    on<MarkInsightRead>(_onMarkRead);
    on<DismissInsight>(_onDismiss);
  }

  Future<void> _onLoad(
    LoadCoachInsights event,
    Emitter<CoachInsightsState> emit,
  ) async {
    _groupId = event.groupId;
    _typeFilter = null;
    _unreadOnly = false;
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshCoachInsights event,
    Emitter<CoachInsightsState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _onFilterByType(
    FilterByType event,
    Emitter<CoachInsightsState> emit,
  ) async {
    _typeFilter = event.type;
    await _fetch(emit);
  }

  Future<void> _onFilterUnread(
    FilterUnreadOnly event,
    Emitter<CoachInsightsState> emit,
  ) async {
    _unreadOnly = event.unreadOnly;
    await _fetch(emit);
  }

  Future<void> _onMarkRead(
    MarkInsightRead event,
    Emitter<CoachInsightsState> emit,
  ) async {
    try {
      final insight = await _repo.getById(event.insightId);
      if (insight == null || insight.isRead) return;
      final updated =
          insight.markRead(DateTime.now().millisecondsSinceEpoch);
      await _repo.update(updated);
      await _fetch(emit);
    } on Exception {
      // Silent — UI refresh will eventually show updated state.
    }
  }

  Future<void> _onDismiss(
    DismissInsight event,
    Emitter<CoachInsightsState> emit,
  ) async {
    try {
      final insight = await _repo.getById(event.insightId);
      if (insight == null || insight.dismissed) return;
      await _repo.update(insight.markDismissed());
      await _fetch(emit);
    } on Exception {
      // Silent
    }
  }

  Future<void> _fetch(Emitter<CoachInsightsState> emit) async {
    emit(const CoachInsightsLoading());
    try {
      final raw = _typeFilter != null
          ? await _repo.getByGroupAndType(
              groupId: _groupId, type: _typeFilter!)
          : await _repo.getByGroupId(_groupId);

      final filtered = raw.where((i) {
        if (i.dismissed) return false;
        if (_unreadOnly && i.isRead) return false;
        return true;
      }).toList();

      final unreadCount = await _repo.countUnreadByGroupId(_groupId);

      if (filtered.isEmpty) {
        emit(CoachInsightsEmpty(
          typeFilter: _typeFilter,
          unreadOnly: _unreadOnly,
        ));
        return;
      }

      emit(CoachInsightsLoaded(
        insights: filtered,
        unreadCount: unreadCount,
        typeFilter: _typeFilter,
        unreadOnly: _unreadOnly,
      ));
    } on Exception catch (e) {
      emit(CoachInsightsError('Erro ao carregar insights: $e'));
    }
  }
}
