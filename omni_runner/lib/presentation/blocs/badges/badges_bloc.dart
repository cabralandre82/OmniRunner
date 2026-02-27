import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_state.dart';

class BadgesBloc extends Bloc<BadgesEvent, BadgesState> {
  final IBadgeAwardRepo _awardRepo;
  final List<BadgeEntity> _catalog;

  String _userId = '';

  BadgesBloc({
    required IBadgeAwardRepo awardRepo,
    required List<BadgeEntity> catalog,
  })  : _awardRepo = awardRepo,
        _catalog = catalog,
        super(const BadgesInitial()) {
    on<LoadBadges>(_onLoad);
    on<RefreshBadges>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadBadges event,
    Emitter<BadgesState> emit,
  ) async {
    _userId = event.userId;
    emit(const BadgesLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshBadges event,
    Emitter<BadgesState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<BadgesState> emit) async {
    try {
      await _syncFromServer();
      final awards = await _awardRepo.getByUserId(_userId);
      emit(BadgesLoaded(catalog: _catalog, awards: awards));
    } on Exception catch (e) {
      emit(BadgesError('Erro ao carregar conquistas: $e'));
    }
  }

  Future<void> _syncFromServer() async {
    if (!AppConfig.isSupabaseReady || _userId.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('badge_awards')
          .select('id, user_id, badge_id, trigger_session_id, unlocked_at_ms, xp_awarded, coins_awarded')
          .eq('user_id', _userId)
          .order('unlocked_at_ms', ascending: false);
      for (final r in rows) {
        final award = BadgeAwardEntity(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          badgeId: r['badge_id'] as String,
          triggerSessionId: r['trigger_session_id'] as String?,
          unlockedAtMs: (r['unlocked_at_ms'] as num).toInt(),
          xpAwarded: (r['xp_awarded'] as num?)?.toInt() ?? 0,
          coinsAwarded: (r['coins_awarded'] as num?)?.toInt() ?? 0,
        );
        await _awardRepo.save(award);
      }
    } on Exception {
      // Offline — use local data
    }
  }
}
