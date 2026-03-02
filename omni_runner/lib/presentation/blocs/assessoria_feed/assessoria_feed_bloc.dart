import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/entities/feed_item_entity.dart';
import 'package:omni_runner/domain/repositories/i_feed_remote_source.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_state.dart';

class AssessoriaFeedBloc
    extends Bloc<AssessoriaFeedEvent, AssessoriaFeedState> {
  static const _pageSize = 30;

  final IFeedRemoteSource _remote;
  String _groupId = '';

  AssessoriaFeedBloc({required IFeedRemoteSource remote})
      : _remote = remote,
        super(const FeedInitial()) {
    on<LoadFeed>(_onLoad);
    on<LoadMoreFeed>(_onLoadMore);
    on<RefreshFeed>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadFeed event,
    Emitter<AssessoriaFeedState> emit,
  ) async {
    _groupId = event.groupId;
    emit(const FeedLoading());
    try {
      final items = await _fetchPage(null);
      if (items.isEmpty) {
        emit(const FeedEmpty());
      } else {
        emit(FeedLoaded(
          items: items,
          hasMore: items.length >= _pageSize,
        ));
      }
    } on Exception catch (e) {
      emit(FeedError('Não foi possível carregar o feed: $e'));
    }
  }

  Future<void> _onLoadMore(
    LoadMoreFeed _,
    Emitter<AssessoriaFeedState> emit,
  ) async {
    final current = state;
    if (current is! FeedLoaded || !current.hasMore || current.loadingMore) {
      return;
    }

    emit(current.copyWith(loadingMore: true));
    try {
      final beforeMs = current.items.last.createdAtMs;
      final older = await _fetchPage(beforeMs);
      emit(current.copyWith(
        items: [...current.items, ...older],
        hasMore: older.length >= _pageSize,
        loadingMore: false,
      ));
    } on Exception {
      emit(current.copyWith(loadingMore: false));
    }
  }

  Future<void> _onRefresh(
    RefreshFeed _,
    Emitter<AssessoriaFeedState> emit,
  ) async {
    try {
      final items = await _fetchPage(null);
      if (items.isEmpty) {
        emit(const FeedEmpty());
      } else {
        emit(FeedLoaded(
          items: items,
          hasMore: items.length >= _pageSize,
        ));
      }
    } on Exception {
      // Keep current state on refresh failure
    }
  }

  Future<List<FeedItemEntity>> _fetchPage(int? beforeMs) =>
      _remote.fetchFeed(
        groupId: _groupId,
        limit: _pageSize,
        beforeMs: beforeMs,
      );
}
