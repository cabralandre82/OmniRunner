import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/coaching_tag_entity.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';
import 'package:omni_runner/domain/repositories/i_crm_repo.dart';
import 'package:omni_runner/domain/usecases/crm/list_crm_athletes.dart';
import 'package:omni_runner/domain/usecases/crm/manage_tags.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_event.dart';
import 'package:omni_runner/presentation/blocs/crm_list/crm_list_state.dart';

class CrmListBloc extends Bloc<CrmListEvent, CrmListState> {
  final ListCrmAthletes _listCrmAthletes;
  final ManageTags _manageTags;

  static const _pageSize = 50;

  String _groupId = '';
  List<String> _activeTagFilters = [];
  MemberStatusValue? _activeStatusFilter;

  CrmListBloc({
    required ListCrmAthletes listCrmAthletes,
    required ManageTags manageTags,
  })  : _listCrmAthletes = listCrmAthletes,
        _manageTags = manageTags,
        super(const CrmListInitial()) {
    on<LoadCrmAthletes>(_onLoadCrmAthletes);
    on<RefreshCrmAthletes>(_onRefreshCrmAthletes);
    on<LoadMoreCrmAthletes>(_onLoadMoreCrmAthletes);
    on<LoadGroupTags>(_onLoadGroupTags);
  }

  Future<void> _onLoadCrmAthletes(
    LoadCrmAthletes event,
    Emitter<CrmListState> emit,
  ) async {
    _groupId = event.groupId;
    _activeTagFilters = event.tagIds ?? [];
    _activeStatusFilter = event.status;

    emit(const CrmListLoading());
    await _fetchAthletesAndTags(emit);
  }

  Future<void> _onRefreshCrmAthletes(
    RefreshCrmAthletes event,
    Emitter<CrmListState> emit,
  ) async {
    if (_groupId.isEmpty) return;
    await _fetchAthletesAndTags(emit);
  }

  Future<void> _onLoadMoreCrmAthletes(
    LoadMoreCrmAthletes event,
    Emitter<CrmListState> emit,
  ) async {
    final current = state;
    if (current is! CrmListLoaded || current.loadingMore || !current.hasMore) {
      return;
    }

    emit(current.copyWith(loadingMore: true));
    try {
      final nextPage = await _listCrmAthletes(
        groupId: _groupId,
        tagIds: _activeTagFilters.isEmpty ? null : _activeTagFilters,
        status: _activeStatusFilter,
        limit: _pageSize,
        offset: current.athletes.length,
      );

      emit(current.copyWith(
        athletes: [...current.athletes, ...nextPage],
        hasMore: nextPage.length >= _pageSize,
        loadingMore: false,
      ));
    } on Exception catch (e, st) {
      AppLogger.error('Failed to load more CRM athletes', tag: 'CrmListBloc', error: e, stack: st);
      emit(current.copyWith(loadingMore: false));
    }
  }

  Future<void> _onLoadGroupTags(
    LoadGroupTags event,
    Emitter<CrmListState> emit,
  ) async {
    emit(const CrmListLoading());
    try {
      final tags = await _manageTags.list(event.groupId);
      final athletes = state is CrmListLoaded
          ? (state as CrmListLoaded).athletes
          : <CrmAthleteView>[];
      emit(CrmListLoaded(
        athletes: athletes,
        tags: tags,
        activeTagFilters: _activeTagFilters,
        activeStatusFilter: _activeStatusFilter,
      ));
    } on Exception catch (e) {
      emit(CrmListError('Erro ao carregar tags: $e'));
    }
  }

  Future<void> _fetchAthletesAndTags(Emitter<CrmListState> emit) async {
    try {
      final results = await Future.wait([
        _listCrmAthletes(
          groupId: _groupId,
          tagIds: _activeTagFilters.isEmpty ? null : _activeTagFilters,
          status: _activeStatusFilter,
          limit: _pageSize,
          offset: 0,
        ),
        _manageTags.list(_groupId),
      ]);

      final athletes = results[0] as List<CrmAthleteView>;
      final tags = results[1] as List<CoachingTagEntity>;

      emit(CrmListLoaded(
        athletes: athletes,
        tags: tags,
        activeTagFilters: _activeTagFilters,
        activeStatusFilter: _activeStatusFilter,
        hasMore: athletes.length >= _pageSize,
      ));
    } on Exception catch (e, st) {
      AppLogger.error('Failed to load CRM', tag: 'CrmListBloc', error: e, stack: st);
      emit(CrmListError('Erro ao carregar CRM: $e'));
    }
  }
}
