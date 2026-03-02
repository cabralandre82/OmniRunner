import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_challenges_remote_source.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/settle_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:uuid/uuid.dart';

class ChallengesBloc extends Bloc<ChallengesEvent, ChallengesState> {
  static const _tag = 'ChallengesBloc';

  final IChallengeRepo _challengeRepo;
  final IChallengesRemoteSource _remote;
  final CreateChallenge _createChallenge;
  final JoinChallenge _joinChallenge;
  final CancelChallenge _cancelChallenge;
  final StartChallenge _startChallenge;
  final EvaluateChallenge _evaluateChallenge;
  final SettleChallenge _settleChallenge;

  String _currentUserId = '';

  ChallengesBloc({
    required IChallengeRepo challengeRepo,
    required IChallengesRemoteSource remote,
    required CreateChallenge createChallenge,
    required JoinChallenge joinChallenge,
    required CancelChallenge cancelChallenge,
    required StartChallenge startChallenge,
    required EvaluateChallenge evaluateChallenge,
    required SettleChallenge settleChallenge,
  })  : _challengeRepo = challengeRepo,
        _remote = remote,
        _createChallenge = createChallenge,
        _joinChallenge = joinChallenge,
        _cancelChallenge = cancelChallenge,
        _startChallenge = startChallenge,
        _evaluateChallenge = evaluateChallenge,
        _settleChallenge = settleChallenge,
        super(const ChallengesInitial()) {
    on<LoadChallenges>(_onLoad);
    on<CreateChallengeRequested>(_onCreate);
    on<InviteToChallengeRequested>(_onInvite);
    on<JoinChallengeRequested>(_onJoin);
    on<DeclineChallengeRequested>(_onDecline);
    on<CancelChallengeRequested>(_onCancel);
    on<ViewChallengeDetails>(_onViewDetails);
  }

  Future<void> _onLoad(
    LoadChallenges event,
    Emitter<ChallengesState> emit,
  ) async {
    _currentUserId = event.userId;
    emit(const ChallengesLoading());
    try {
      // 1. Sync from backend (non-blocking for offline)
      await _syncFromBackend(event.userId);

      // 2. Load from local Isar (now up-to-date)
      final challenges = await _challengeRepo.getByUserId(event.userId);
      await _runLifecycleChecks(challenges);
      final refreshed = await _challengeRepo.getByUserId(event.userId);
      emit(ChallengesLoaded(refreshed));
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  /// Fetches challenges from backend and merges into local repo.
  /// Gracefully degrades if offline.
  Future<void> _syncFromBackend(String userId) async {
    try {
      final remoteChallenges = await _remote.fetchMyChallenges();

      for (final remoteEntity in remoteChallenges) {
        try {
          final local = await _challengeRepo.getById(remoteEntity.id);

          if (local == null) {
            await _challengeRepo.save(remoteEntity);
            AppLogger.debug('Synced new challenge ${remoteEntity.id}', tag: _tag);
          } else {
            final merged = _mergeChallenge(local, remoteEntity);
            if (merged != local) {
              await _challengeRepo.update(merged);
              AppLogger.debug('Merged challenge ${merged.id}', tag: _tag);
            }
          }
        } on Exception catch (e) {
          AppLogger.warn('Failed to merge challenge: $e', tag: _tag);
        }
      }
    } on Exception catch (e) {
      AppLogger.warn('Backend sync failed — using local data: $e', tag: _tag);
    }
  }

  /// Merges remote state into local: remote status & participants take
  /// precedence, but local progress data (contributing sessions) is preserved.
  ChallengeEntity _mergeChallenge(ChallengeEntity local, ChallengeEntity remote) {
    final mergedParticipants = <ChallengeParticipantEntity>[];

    for (final rp in remote.participants) {
      final lp = local.participants
          .where((p) => p.userId == rp.userId)
          .firstOrNull;
      if (lp != null) {
        mergedParticipants.add(ChallengeParticipantEntity(
          userId: rp.userId,
          displayName: rp.displayName.isNotEmpty ? rp.displayName : lp.displayName,
          status: rp.status,
          respondedAtMs: rp.respondedAtMs ?? lp.respondedAtMs,
          progressValue: rp.progressValue > lp.progressValue ? rp.progressValue : lp.progressValue,
          contributingSessionIds: lp.contributingSessionIds,
          lastSubmittedAtMs: lp.lastSubmittedAtMs,
          groupId: rp.groupId ?? lp.groupId,
          team: rp.team ?? lp.team,
        ));
      } else {
        mergedParticipants.add(rp);
      }
    }

    // Add local-only participants not present in remote
    for (final lp in local.participants) {
      if (!mergedParticipants.any((p) => p.userId == lp.userId)) {
        mergedParticipants.add(lp);
      }
    }

    return ChallengeEntity(
      id: remote.id,
      creatorUserId: remote.creatorUserId,
      status: _laterStatus(local.status, remote.status),
      type: remote.type,
      rules: remote.rules,
      participants: mergedParticipants,
      createdAtMs: remote.createdAtMs,
      startsAtMs: remote.startsAtMs ?? local.startsAtMs,
      endsAtMs: remote.endsAtMs ?? local.endsAtMs,
      title: remote.title ?? local.title,
      acceptDeadlineMs: remote.acceptDeadlineMs ?? local.acceptDeadlineMs,
    );
  }

  /// Returns whichever status is further along in the lifecycle.
  ChallengeStatus _laterStatus(ChallengeStatus a, ChallengeStatus b) {
    const order = {
      ChallengeStatus.pending: 0,
      ChallengeStatus.active: 1,
      ChallengeStatus.completing: 2,
      ChallengeStatus.completed: 3,
      ChallengeStatus.cancelled: 3,
      ChallengeStatus.expired: 3,
    };
    return (order[b] ?? 0) >= (order[a] ?? 0) ? b : a;
  }

  /// Checks all challenges for lifecycle transitions that should happen:
  /// 1. Scheduled pending challenges whose start time has arrived → activate
  /// 2. Active challenges whose window has expired → settle via backend EF
  Future<void> _runLifecycleChecks(List<ChallengeEntity> challenges) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (final c in challenges) {
      try {
        if (_shouldAutoActivate(c, nowMs)) {
          await _startChallenge.call(challengeId: c.id, nowMs: nowMs);
          AppLogger.info(
            'Auto-activated scheduled challenge ${c.id}',
            tag: _tag,
          );
        } else if (_shouldAutoComplete(c, nowMs)) {
          await _settleViaBackend(c.id);
        }
      } on GamificationFailure catch (e) {
        AppLogger.warn(
          'Lifecycle check failed for ${c.id}: ${e.runtimeType}',
          tag: _tag,
        );
      }
    }
  }

  /// Delegates challenge settlement to the backend.
  /// Falls back to local evaluation only if backend is unreachable.
  Future<void> _settleViaBackend(String challengeId) async {
    final handled = await _remote.settleChallenge(challengeId);
    if (handled) return;

    // Fallback: local evaluation (may have incomplete data)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _evaluateChallenge.call(challengeId: challengeId, nowMs: nowMs);
    await _settleChallenge.call(
      challengeId: challengeId,
      uuidGenerator: () => const Uuid().v4(),
      nowMs: nowMs,
    );
    AppLogger.info('Challenge $challengeId settled locally (fallback)', tag: _tag);
  }

  bool _shouldAutoActivate(ChallengeEntity c, int nowMs) {
    if (c.status != ChallengeStatus.pending) return false;
    if (c.rules.startMode != ChallengeStartMode.scheduled) return false;
    final fixedStart = c.rules.fixedStartMs;
    if (fixedStart == null || fixedStart > nowMs) return false;
    final accepted = c.acceptedCount;
    if (c.type == ChallengeType.oneVsOne && accepted != 2) return false;
    if ((c.type == ChallengeType.group || c.type == ChallengeType.team) && accepted < 2) return false;
    return true;
  }

  bool _shouldAutoComplete(ChallengeEntity c, int nowMs) {
    if (c.status != ChallengeStatus.active) return false;
    final endsAt = c.endsAtMs;
    return endsAt != null && endsAt <= nowMs;
  }

  Future<void> _onCreate(
    CreateChallengeRequested event,
    Emitter<ChallengesState> emit,
  ) async {
    emit(const ChallengesLoading());
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final id = const Uuid().v4();
      final ChallengeType type;
      switch (event.type) {
        case 'group':
          type = ChallengeType.group;
        case 'team':
          type = ChallengeType.team;
        default:
          type = ChallengeType.oneVsOne;
      }
      final challenge = await _createChallenge.call(
        id: id,
        creatorUserId: event.creatorUserId,
        creatorDisplayName: event.creatorDisplayName,
        type: type,
        rules: event.rules,
        createdAtMs: nowMs,
        title: event.title,
      );

      _syncChallengeToBackend(challenge, event.creatorDisplayName);

      emit(ChallengeCreated(challenge));
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  /// Sync a newly created challenge to the backend (fire-and-forget).
  void _syncChallengeToBackend(ChallengeEntity c, String creatorDisplayName) {
    final dbType = switch (c.type) {
      ChallengeType.oneVsOne => 'one_vs_one',
      ChallengeType.group => 'group',
      ChallengeType.team => 'team',
    };
    final dbGoal = switch (c.rules.goal) {
      ChallengeGoal.fastestAtDistance => 'fastest_at_distance',
      ChallengeGoal.mostDistance => 'most_distance',
      ChallengeGoal.bestPaceAtDistance => 'best_pace_at_distance',
      ChallengeGoal.collectiveDistance => 'collective_distance',
    };
    final startMode = c.rules.startMode == ChallengeStartMode.onAccept
        ? 'on_accept'
        : 'scheduled';
    final antiCheat = c.rules.antiCheatPolicy == ChallengeAntiCheatPolicy.strict
        ? 'strict'
        : 'standard';

    final payload = {
      'id': c.id,
      'type': dbType,
      'title': c.title,
      'goal': dbGoal,
      'target': c.rules.target,
      'window_ms': c.rules.windowMs,
      'start_mode': startMode,
      'fixed_start_ms': c.rules.fixedStartMs,
      'entry_fee_coins': c.rules.entryFeeCoins,
      'min_session_distance_m': c.rules.minSessionDistanceM,
      'anti_cheat_policy': antiCheat,
      'created_at_ms': c.createdAtMs,
      'creator_display_name': creatorDisplayName,
      if (c.rules.acceptWindowMin != null) 'accept_window_min': c.rules.acceptWindowMin,
      if (c.rules.maxParticipants != null) 'max_participants': c.rules.maxParticipants,
    };

    _remote.syncNewChallenge(payload);
  }

  Future<void> _onInvite(
    InviteToChallengeRequested event,
    Emitter<ChallengesState> emit,
  ) async {
    try {
      final challenge = await _challengeRepo.getById(event.challengeId);
      if (challenge == null) {
        emit(ChallengesError(
          _failureMessage(ChallengeNotFound(event.challengeId)),
          failure: ChallengeNotFound(event.challengeId),
        ));
        return;
      }

      if (challenge.status != ChallengeStatus.pending) {
        emit(ChallengesError(
          'Só é possível convidar em desafios pendentes.',
          failure: InvalidChallengeStatus(
            event.challengeId, 'pending', challenge.status.name,
          ),
        ));
        return;
      }

      if (challenge.participants.any((p) => p.userId == event.inviteeUserId)) {
        emit(ChallengesError(
          'Este corredor já foi convidado.',
          failure: AlreadyParticipant(event.inviteeUserId, event.challengeId),
        ));
        return;
      }

      final updatedParticipants = [
        ...challenge.participants,
        ChallengeParticipantEntity(
          userId: event.inviteeUserId,
          displayName: event.inviteeDisplayName,
          status: ParticipantStatus.invited,
        ),
      ];

      final updated = challenge.copyWith(participants: updatedParticipants);
      await _challengeRepo.update(updated);

      emit(ChallengeDetailLoaded(challenge: updated));
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  Future<void> _onJoin(
    JoinChallengeRequested event,
    Emitter<ChallengesState> emit,
  ) async {
    try {
      final updated = await _joinChallenge.call(
        challengeId: event.challengeId,
        userId: event.userId,
        respondedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _tryAutoStart(updated);

      if (_currentUserId.isNotEmpty) {
        add(LoadChallenges(_currentUserId));
      }
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  /// When all required participants have accepted and start mode is
  /// [ChallengeStartMode.onAccept], automatically activate the challenge.
  Future<void> _tryAutoStart(ChallengeEntity challenge) async {
    if (challenge.status != ChallengeStatus.pending) return;
    if (challenge.rules.startMode != ChallengeStartMode.onAccept) return;

    final accepted = challenge.acceptedCount;
    final bool shouldStart;
    if (challenge.type == ChallengeType.oneVsOne) {
      shouldStart = accepted == 2;
    } else if (challenge.type == ChallengeType.team) {
      final teamA = challenge.participants.where((p) => p.team == 'A' && p.status == ParticipantStatus.accepted).length;
      final teamB = challenge.participants.where((p) => p.team == 'B' && p.status == ParticipantStatus.accepted).length;
      shouldStart = teamA >= 1 && teamB >= 1 && teamA == teamB;
    } else {
      shouldStart = accepted >= 2;
    }

    if (!shouldStart) return;

    try {
      await _startChallenge.call(
        challengeId: challenge.id,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on GamificationFailure {
      // Start preconditions not met — challenge stays pending
    }
  }

  Future<void> _onDecline(
    DeclineChallengeRequested event,
    Emitter<ChallengesState> emit,
  ) async {
    try {
      final challenge = await _challengeRepo.getById(event.challengeId);
      if (challenge == null) {
        emit(ChallengesError(
          _failureMessage(ChallengeNotFound(event.challengeId)),
          failure: ChallengeNotFound(event.challengeId),
        ));
        return;
      }

      final idx = challenge.participants.indexWhere(
        (p) => p.userId == event.userId,
      );
      if (idx == -1) return;

      final updatedParticipants = List.of(challenge.participants);
      updatedParticipants[idx] = challenge.participants[idx].copyWith(
        status: ParticipantStatus.declined,
        respondedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _challengeRepo.update(
        challenge.copyWith(participants: updatedParticipants),
      );

      if (_currentUserId.isNotEmpty) {
        add(LoadChallenges(_currentUserId));
      }
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  Future<void> _onCancel(
    CancelChallengeRequested event,
    Emitter<ChallengesState> emit,
  ) async {
    try {
      await _cancelChallenge.call(
        challengeId: event.challengeId,
        userId: event.userId,
      );
      if (_currentUserId.isNotEmpty) {
        add(LoadChallenges(_currentUserId));
      }
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  Future<void> _onViewDetails(
    ViewChallengeDetails event,
    Emitter<ChallengesState> emit,
  ) async {
    emit(const ChallengesLoading());
    try {
      final challenge = await _challengeRepo.getById(event.challengeId);
      if (challenge == null) {
        emit(ChallengesError(
          'Desafio não encontrado.',
          failure: ChallengeNotFound(event.challengeId),
        ));
        return;
      }
      final result = await _challengeRepo.getResultByChallengeId(
        event.challengeId,
      );
      emit(ChallengeDetailLoaded(challenge: challenge, result: result));
    } on GamificationFailure catch (e) {
      emit(ChallengesError(_failureMessage(e), failure: e));
    }
  }

  static String _failureMessage(GamificationFailure f) => switch (f) {
        ChallengeNotFound() => 'Desafio não encontrado.',
        InvalidChallengeStatus() => 'Desafio em status inválido para esta ação.',
        NotAParticipant() => 'Você não participa deste desafio.',
        AlreadyParticipant() => 'Você já participa deste desafio.',
        ChallengeFull() => 'Desafio lotado (máximo 50 participantes).',
        InsufficientBalance() => 'OmniCoins insuficientes para participar.',
        NotChallengeCreator() => 'Apenas o criador pode cancelar o desafio.',
        UnverifiedSession() => 'Sessão não verificada.',
        DailyLimitReached() => 'Limite diário de recompensas atingido.',
        SessionBelowMinimum() => 'Sessão abaixo da distância mínima.',
        SessionAlreadySubmitted() => 'Sessão já submetida.',
        DuplicateLedgerEntry() => 'Operação já realizada.',
        SessionNotCompleted() => 'Sessão não finalizada.',
        SessionNoUser() => 'Sessão sem usuário associado.',
      };
}
