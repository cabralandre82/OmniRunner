import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/screens/challenge_invite_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeChallengesBloc extends Cubit<ChallengesState>
    implements ChallengesBloc {
  _FakeChallengesBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

final _challenge = ChallengeEntity(
  id: 'c1',
  creatorUserId: 'test-user',
  status: ChallengeStatus.pending,
  type: ChallengeType.oneVsOne,
  rules: const ChallengeRulesEntity(
    goal: ChallengeGoal.fastestAtDistance,
    target: 5000,
    windowMs: 10800000,
    entryFeeCoins: 50,
  ),
  participants: [
    const ChallengeParticipantEntity(
      userId: 'test-user',
      displayName: 'Creator User',
      status: ParticipantStatus.accepted,
    ),
  ],
  createdAtMs: 1700000000000,
  title: 'Corrida 5K',
);

void main() {
  group('ChallengeInviteScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });

    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with title "Convidar Oponente"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Convidar Oponente'), findsOneWidget);
    });

    testWidgets('shows success header', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Desafio criado!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('shows challenge title', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Corrida 5K'), findsOneWidget);
    });

    testWidgets('shows share button and deep link', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Enviar convite'), findsOneWidget);
      expect(
        find.textContaining('https://omnirunner.app/challenge/'),
        findsOneWidget,
      );
    });

    testWidgets('shows concluir button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Concluir'), findsOneWidget);
    });

    testWidgets('shows participant list', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: ChallengeInviteScreen(challenge: _challenge),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Participantes'), findsOneWidget);
      expect(find.text('Creator User'), findsOneWidget);
    });
  });
}
