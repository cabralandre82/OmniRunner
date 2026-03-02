import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_progression_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_event.dart';
import 'package:omni_runner/presentation/blocs/progression/progression_state.dart';

class ProgressionBloc extends Bloc<ProgressionEvent, ProgressionState> {
  final IProfileProgressRepo _profileRepo;
  final IXpTransactionRepo _xpRepo;
  final IProgressionRemoteSource _remote;

  String _userId = '';

  ProgressionBloc({
    required IProfileProgressRepo profileRepo,
    required IXpTransactionRepo xpRepo,
    required IProgressionRemoteSource remote,
  })  : _profileRepo = profileRepo,
        _xpRepo = xpRepo,
        _remote = remote,
        super(const ProgressionInitial()) {
    on<LoadProgression>(_onLoad);
    on<RefreshProgression>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    _userId = event.userId;
    emit(const ProgressionLoading());
    await _fetch(emit);
  }

  Future<void> _onRefresh(
    RefreshProgression event,
    Emitter<ProgressionState> emit,
  ) async {
    if (_userId.isEmpty) return;
    await _fetch(emit);
  }

  Future<void> _fetch(Emitter<ProgressionState> emit) async {
    try {
      // Server-side recalculation (best-effort)
      await _remote.recalculateAndEvaluate(_userId);

      // Sync profile progress from remote to local
      final remoteProfile = await _remote.fetchProfileProgress(_userId);
      if (remoteProfile != null) {
        await _profileRepo.save(remoteProfile);
      }

      // Sync XP transactions from remote to local
      final remoteTx = await _remote.fetchXpTransactions(_userId);
      for (final tx in remoteTx) {
        await _xpRepo.append(tx);
      }

      // Fetch weekly goal and badges directly from remote
      final weeklyGoal = await _remote.fetchWeeklyGoal(_userId);
      final badges = await _remote.fetchBadges(_userId);

      // Read profile and XP from local repos (always available offline)
      final profile = await _profileRepo.getByUserId(_userId);
      final xpHistory = await _xpRepo.getByUserId(_userId);

      emit(ProgressionLoaded(
        profile: profile,
        recentXp: xpHistory,
        weeklyGoal: weeklyGoal,
        badgeCatalog: badges.catalog,
        earnedBadgeIds: badges.earnedIds,
      ));
    } on Exception catch (e) {
      emit(ProgressionError('Erro ao carregar progressão: $e'));
    }
  }
}
