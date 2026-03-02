import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_challenges_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/cancel_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/create_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/evaluate_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/join_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/ledger_service.dart';
import 'package:omni_runner/domain/usecases/gamification/settle_challenge.dart';
import 'package:omni_runner/domain/usecases/gamification/start_challenge.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';

// ── Mocks (interfaces only — final classes use real instances) ──

class MockChallengeRepo extends Mock implements IChallengeRepo {}

class MockLedgerRepo extends Mock implements ILedgerRepo {}

class MockWalletRepo extends Mock implements IWalletRepo {}

class MockChallengesRemoteSource extends Mock
    implements IChallengesRemoteSource {}

// ── Fixtures ──

const _userId = 'user-1';
const _otherUserId = 'user-2';

const _rules = ChallengeRulesEntity(
  goal: ChallengeGoal.mostDistance,
  windowMs: 604800000,
);

ChallengeEntity _pendingChallenge({
  String id = 'ch-1',
  List<ChallengeParticipantEntity>? participants,
}) =>
    ChallengeEntity(
      id: id,
      creatorUserId: _userId,
      status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: _rules,
      participants: participants ??
          const [
            ChallengeParticipantEntity(
              userId: _userId,
              displayName: 'Alice',
              status: ParticipantStatus.accepted,
            ),
            ChallengeParticipantEntity(
              userId: _otherUserId,
              displayName: 'Bob',
              status: ParticipantStatus.invited,
            ),
          ],
      createdAtMs: 1000000,
    );

ChallengeEntity _activeChallenge({String id = 'ch-1'}) => ChallengeEntity(
      id: id,
      creatorUserId: _userId,
      status: ChallengeStatus.active,
      type: ChallengeType.oneVsOne,
      rules: _rules,
      participants: const [
        ChallengeParticipantEntity(
          userId: _userId,
          displayName: 'Alice',
          status: ParticipantStatus.accepted,
        ),
        ChallengeParticipantEntity(
          userId: _otherUserId,
          displayName: 'Bob',
          status: ParticipantStatus.accepted,
        ),
      ],
      createdAtMs: 1000000,
      startsAtMs: 2000000,
      endsAtMs: 2000000 + 604800000,
    );

/// Collects [count] states from [bloc.stream] or times out.
Future<List<ChallengesState>> _collectStates(
  ChallengesBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <ChallengesState>[];
  final completer = Completer<void>();
  final sub = bloc.stream.listen((s) {
    states.add(s);
    if (states.length >= count && !completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future.timeout(timeout, onTimeout: () {});
  await sub.cancel();
  return states;
}

void main() {
  late MockChallengeRepo repo;
  late MockLedgerRepo ledgerRepo;
  late MockWalletRepo walletRepo;
  late MockChallengesRemoteSource remote;

  late CreateChallenge createChallenge;
  late JoinChallenge joinChallenge;
  late CancelChallenge cancelChallenge;
  late StartChallenge startChallenge;
  late EvaluateChallenge evaluateChallenge;
  late SettleChallenge settleChallenge;

  setUp(() {
    repo = MockChallengeRepo();
    ledgerRepo = MockLedgerRepo();
    walletRepo = MockWalletRepo();
    remote = MockChallengesRemoteSource();

    // Default: remote returns empty (offline fallback)
    when(() => remote.fetchMyChallenges()).thenAnswer((_) async => []);
    when(() => remote.syncNewChallenge(any())).thenAnswer((_) async {});
    when(() => remote.settleChallenge(any())).thenAnswer((_) async => false);

    createChallenge = CreateChallenge(challengeRepo: repo);
    joinChallenge = JoinChallenge(challengeRepo: repo);
    cancelChallenge = CancelChallenge(challengeRepo: repo);
    startChallenge = StartChallenge(challengeRepo: repo);
    evaluateChallenge = EvaluateChallenge(challengeRepo: repo);
    settleChallenge = SettleChallenge(
      challengeRepo: repo,
      ledgerService: LedgerService(
        ledgerRepo: ledgerRepo,
        walletRepo: walletRepo,
      ),
    );
  });

  ChallengesBloc buildBloc() => ChallengesBloc(
        challengeRepo: repo,
        remote: remote,
        createChallenge: createChallenge,
        joinChallenge: joinChallenge,
        cancelChallenge: cancelChallenge,
        startChallenge: startChallenge,
        evaluateChallenge: evaluateChallenge,
        settleChallenge: settleChallenge,
      );

  setUpAll(() {
    registerFallbackValue(_pendingChallenge());
  });

  group('ChallengesBloc', () {
    test('initial state is ChallengesInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const ChallengesInitial());
      bloc.close();
    });

    // ── LoadChallenges ──

    group('LoadChallenges', () {
      test('emits [Loading, Loaded] with challenges from repo', () async {
        final challenges = [_pendingChallenge()];
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => challenges);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], isA<ChallengesLoaded>());
        expect((states[1] as ChallengesLoaded).challenges.length, 1);
        await bloc.close();
      });

      test('emits [Loading, Loaded] with empty list', () async {
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], const ChallengesLoaded([]));
        await bloc.close();
      });

      test('emits [Loading, Error] on GamificationFailure', () async {
        when(() => repo.getByUserId(_userId))
            .thenThrow(const ChallengeNotFound('ch-x'));

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], isA<ChallengesError>());
        expect(
          (states[1] as ChallengesError).message,
          contains('não encontrado'),
        );
        await bloc.close();
      });
    });

    // ── CreateChallengeRequested ──

    group('CreateChallengeRequested', () {
      test('emits [Loading, ChallengeCreated] on success', () async {
        when(() => repo.save(any())).thenAnswer((_) async {});

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const CreateChallengeRequested(
          creatorUserId: _userId,
          creatorDisplayName: 'Alice',
          type: 'one_vs_one',
          rules: _rules,
          title: 'Test',
        ));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], isA<ChallengeCreated>());
        final created = (states[1] as ChallengeCreated).challenge;
        expect(created.creatorUserId, _userId);
        expect(created.status, ChallengeStatus.pending);
        expect(created.participants.length, 1);
        expect(created.participants[0].status, ParticipantStatus.accepted);
        await bloc.close();
      });

      test('creates group challenge when type is "group"', () async {
        when(() => repo.save(any())).thenAnswer((_) async {});

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const CreateChallengeRequested(
          creatorUserId: _userId,
          creatorDisplayName: 'Alice',
          type: 'group',
          rules: _rules,
        ));
        final states = await future;

        final created = (states[1] as ChallengeCreated).challenge;
        expect(created.type, ChallengeType.group);
        await bloc.close();
      });

      test('creates team challenge when type is "team"', () async {
        when(() => repo.save(any())).thenAnswer((_) async {});

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const CreateChallengeRequested(
          creatorUserId: _userId,
          creatorDisplayName: 'Alice',
          type: 'team',
          rules: _rules,
        ));
        final states = await future;

        final created = (states[1] as ChallengeCreated).challenge;
        expect(created.type, ChallengeType.team);
        await bloc.close();
      });
    });

    // ── JoinChallengeRequested ──

    group('JoinChallengeRequested', () {
      test('emits Error when user is not a participant', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const JoinChallengeRequested(
          challengeId: 'ch-1',
          userId: 'stranger',
        ));
        final states = await future;

        expect(states[0], isA<ChallengesError>());
        expect(
          (states[0] as ChallengesError).message,
          contains('não participa'),
        );
        await bloc.close();
      });

      test('emits Error when challenge not found', () async {
        when(() => repo.getById('ch-missing'))
            .thenAnswer((_) async => null);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const JoinChallengeRequested(
          challengeId: 'ch-missing',
          userId: _otherUserId,
        ));
        final states = await future;

        expect(states[0], isA<ChallengesError>());
        await bloc.close();
      });
    });

    // ── CancelChallengeRequested ──

    group('CancelChallengeRequested', () {
      test('emits Error when not the creator', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const CancelChallengeRequested(
          challengeId: 'ch-1',
          userId: _otherUserId,
        ));
        final states = await future;

        expect(states[0], isA<ChallengesError>());
        expect(
          (states[0] as ChallengesError).message,
          contains('criador'),
        );
        await bloc.close();
      });

      test('re-loads after successful cancel', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());
        when(() => repo.update(any())).thenAnswer((_) async {});
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        // Load first to set _currentUserId
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        await future;

        // Cancel
        future = _collectStates(bloc, count: 2);
        bloc.add(const CancelChallengeRequested(
          challengeId: 'ch-1',
          userId: _userId,
        ));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], const ChallengesLoaded([]));
        await bloc.close();
      });
    });

    // ── DeclineChallengeRequested ──

    group('DeclineChallengeRequested', () {
      test('updates participant to declined and re-loads', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());
        when(() => repo.update(any())).thenAnswer((_) async {});
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        var future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        await future;

        future = _collectStates(bloc, count: 2);
        bloc.add(const DeclineChallengeRequested(
          challengeId: 'ch-1',
          userId: _otherUserId,
        ));
        final states = await future;

        verify(() => repo.update(any(
          that: isA<ChallengeEntity>().having(
            (c) => c.participants
                .firstWhere((p) => p.userId == _otherUserId)
                .status,
            'declined status',
            ParticipantStatus.declined,
          ),
        ))).called(1);
        await bloc.close();
      });
    });

    // ── ViewChallengeDetails ──

    group('ViewChallengeDetails', () {
      test('emits [Loading, ChallengeDetailLoaded] with result', () async {
        final challenge = _activeChallenge();
        const result = ChallengeResultEntity(
          challengeId: 'ch-1',
          goal: ChallengeGoal.mostDistance,
          results: [],
          totalCoinsDistributed: 0,
          calculatedAtMs: 5000000,
        );
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => challenge);
        when(() => repo.getResultByChallengeId('ch-1'))
            .thenAnswer((_) async => result);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const ViewChallengeDetails('ch-1'));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        final detail = states[1] as ChallengeDetailLoaded;
        expect(detail.challenge.id, 'ch-1');
        expect(detail.result, isNotNull);
        await bloc.close();
      });

      test('emits Error when challenge not found', () async {
        when(() => repo.getById('ch-missing'))
            .thenAnswer((_) async => null);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const ViewChallengeDetails('ch-missing'));
        final states = await future;

        expect(states[0], isA<ChallengesLoading>());
        expect(states[1], isA<ChallengesError>());
        expect(
          (states[1] as ChallengesError).message,
          contains('não encontrado'),
        );
        await bloc.close();
      });

      test('emits detail with null result', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());
        when(() => repo.getResultByChallengeId('ch-1'))
            .thenAnswer((_) async => null);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const ViewChallengeDetails('ch-1'));
        final states = await future;

        final detail = states[1] as ChallengeDetailLoaded;
        expect(detail.result, isNull);
        await bloc.close();
      });
    });

    // ── InviteToChallengeRequested ──

    group('InviteToChallengeRequested', () {
      test('adds participant and emits ChallengeDetailLoaded', () async {
        final challenge = _pendingChallenge(
          participants: const [
            ChallengeParticipantEntity(
              userId: _userId,
              displayName: 'Alice',
              status: ParticipantStatus.accepted,
            ),
          ],
        );
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => challenge);
        when(() => repo.update(any())).thenAnswer((_) async {});

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const InviteToChallengeRequested(
          challengeId: 'ch-1',
          inviteeUserId: 'user-3',
          inviteeDisplayName: 'Charlie',
        ));
        final states = await future;

        final detail = states[0] as ChallengeDetailLoaded;
        expect(detail.challenge.participants.length, 2);
        expect(detail.challenge.participants[1].userId, 'user-3');
        expect(
          detail.challenge.participants[1].status,
          ParticipantStatus.invited,
        );
        await bloc.close();
      });

      test('emits Error when invitee already a participant', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _pendingChallenge());

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const InviteToChallengeRequested(
          challengeId: 'ch-1',
          inviteeUserId: _otherUserId,
          inviteeDisplayName: 'Bob',
        ));
        final states = await future;

        expect(states[0], isA<ChallengesError>());
        expect(
          (states[0] as ChallengesError).message,
          contains('já foi convidado'),
        );
        await bloc.close();
      });

      test('emits Error when challenge is not pending', () async {
        when(() => repo.getById('ch-1'))
            .thenAnswer((_) async => _activeChallenge());

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1);
        bloc.add(const InviteToChallengeRequested(
          challengeId: 'ch-1',
          inviteeUserId: 'user-3',
          inviteeDisplayName: 'Charlie',
        ));
        final states = await future;

        expect(states[0], isA<ChallengesError>());
        expect(
          (states[0] as ChallengesError).message,
          contains('pendentes'),
        );
        await bloc.close();
      });
    });

    group('Remote sync', () {
      test('merges remote challenges into local repo on Load', () async {
        final remoteChallenge = _activeChallenge(id: 'ch-remote');

        when(() => remote.fetchMyChallenges())
            .thenAnswer((_) async => [remoteChallenge]);
        when(() => repo.getById('ch-remote'))
            .thenAnswer((_) async => null);
        when(() => repo.save(any())).thenAnswer((_) async {});
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => [remoteChallenge]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        final states = await future;
        await bloc.close();

        verify(() => repo.save(any())).called(greaterThanOrEqualTo(1));
        expect(states[1], isA<ChallengesLoaded>());
        expect(
          (states[1] as ChallengesLoaded).challenges.first.id,
          'ch-remote',
        );
      });

      test('loads from local repo when remote returns empty', () async {
        final localChallenge = _pendingChallenge();
        when(() => remote.fetchMyChallenges())
            .thenAnswer((_) async => []);
        when(() => repo.getByUserId(_userId))
            .thenAnswer((_) async => [localChallenge]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadChallenges(_userId));
        final states = await future;
        await bloc.close();

        expect(states[1], isA<ChallengesLoaded>());
        expect(
          (states[1] as ChallengesLoaded).challenges.first.id,
          'ch-1',
        );
      });
    });
  });
}
