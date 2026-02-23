import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/feed_item_entity.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_event.dart';
import 'package:omni_runner/presentation/blocs/assessoria_feed/assessoria_feed_state.dart';

class AssessoriaFeedBloc
    extends Bloc<AssessoriaFeedEvent, AssessoriaFeedState> {
  static const _pageSize = 30;
  String _groupId = '';

  AssessoriaFeedBloc() : super(const FeedInitial()) {
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
      final items = await _fetch(null);
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
      final older = await _fetch(beforeMs);
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
      final items = await _fetch(null);
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

  Future<List<FeedItemEntity>> _fetch(int? beforeMs) async {
    final sb = Supabase.instance.client;

    final params = <String, dynamic>{
      'p_group_id': _groupId,
      'p_limit': _pageSize,
    };
    if (beforeMs != null) {
      params['p_before_ms'] = beforeMs;
    }

    final rows = await sb.rpc('fn_get_assessoria_feed', params: params)
        as List<dynamic>;

    return rows.map((dynamic row) {
      final r = row as Map<String, dynamic>;
      return FeedItemEntity(
        id: r['id'] as String,
        actorUserId: r['actor_user_id'] as String,
        actorName: (r['actor_name'] as String?) ?? 'Corredor',
        eventType: _parseEventType(r['event_type'] as String),
        payload: (r['payload'] as Map<String, dynamic>?) ?? {},
        createdAtMs: (r['created_at_ms'] as num).toInt(),
      );
    }).toList();
  }

  static FeedEventType _parseEventType(String raw) => switch (raw) {
        'session_completed' => FeedEventType.sessionCompleted,
        'challenge_won' => FeedEventType.challengeWon,
        'badge_unlocked' => FeedEventType.badgeUnlocked,
        'championship_started' => FeedEventType.championshipStarted,
        'streak_milestone' => FeedEventType.streakMilestone,
        'level_up' => FeedEventType.levelUp,
        'member_joined' => FeedEventType.memberJoined,
        _ => FeedEventType.sessionCompleted,
      };
}
