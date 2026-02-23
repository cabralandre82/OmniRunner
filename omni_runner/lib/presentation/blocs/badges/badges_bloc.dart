import 'package:flutter_bloc/flutter_bloc.dart';
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
      final awards = await _awardRepo.getByUserId(_userId);
      emit(BadgesLoaded(catalog: _catalog, awards: awards));
    } on Exception catch (e) {
      emit(BadgesError('Erro ao carregar conquistas: $e'));
    }
  }
}
