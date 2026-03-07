import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/screens/challenge_details_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeChallengesBloc extends Cubit<ChallengesState>
    implements ChallengesBloc {
  _FakeChallengesBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-user';

  @override
  String get displayName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

final _challenge = ChallengeEntity(
  id: 'c1',
  creatorUserId: 'test-user',
  status: ChallengeStatus.active,
  type: ChallengeType.oneVsOne,
  rules: const ChallengeRulesEntity(
    goal: ChallengeGoal.fastestAtDistance,
    target: 10000,
    windowMs: 86400000,
    entryFeeCoins: 50,
  ),
  participants: [
    const ChallengeParticipantEntity(
      userId: 'test-user',
      displayName: 'Test User',
      status: ParticipantStatus.accepted,
    ),
    const ChallengeParticipantEntity(
      userId: 'opponent',
      displayName: 'Opponent',
      status: ParticipantStatus.accepted,
    ),
  ],
  createdAtMs: 1700000000000,
  startsAtMs: 1700000000000,
  endsAtMs: 4102444800000,
  title: 'Corrida 10K',
);

void main() {
  final sl = GetIt.instance;

  group('ChallengeDetailsScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      sl.allowReassignment = true;
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows loading indicator for ChallengesLoading state',
        (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesLoading());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for ChallengesError state',
        (tester) async {
      final bloc =
          _FakeChallengesBloc(const ChallengesError('Desafio não encontrado.'));

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Desafio não encontrado.'), findsOneWidget);
    });

    testWidgets('shows challenge details when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(
        ChallengeDetailLoaded(challenge: _challenge),
      );

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Corrida 10K'), findsOneWidget);
      expect(find.text('Como funciona'), findsOneWidget);
    });

    testWidgets('shows participants card when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(
        ChallengeDetailLoaded(challenge: _challenge),
      );

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Participantes (2)'), findsOneWidget);
      expect(find.text('Opponent'), findsOneWidget);
    });

    testWidgets('shows AppBar with title', (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeDetailsScreen(challengeId: 'c1'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
