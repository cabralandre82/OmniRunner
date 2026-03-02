import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_badges_remote_source.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_state.dart';

class BadgesBloc extends Bloc<BadgesEvent, BadgesState> {
  final IBadgeAwardRepo _awardRepo;
  final IBadgesRemoteSource _remote;

  String _userId = '';

  BadgesBloc({
    required IBadgeAwardRepo awardRepo,
    required IBadgesRemoteSource remote,
  })  : _awardRepo = awardRepo,
        _remote = remote,
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
      // Trigger server-side retroactive evaluation (best-effort)
      await _remote.evaluateRetroactive(_userId);

      // Fetch catalog from remote
      final catalog = await _remote.fetchCatalog();

      // Sync awards from remote to local repo
      final remoteAwards = await _remote.fetchAwards(_userId);
      for (final award in remoteAwards) {
        await _awardRepo.save(award);
      }

      // Read from local repo (always available, even offline)
      final awards = await _awardRepo.getByUserId(_userId);
      emit(BadgesLoaded(catalog: catalog, awards: awards));
    } on Exception catch (e) {
      emit(BadgesError('Erro ao carregar conquistas: $e'));
    }
  }
}
