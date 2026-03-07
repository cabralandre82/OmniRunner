import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_friendship_repo.dart';
import 'package:omni_runner/presentation/screens/challenge_result_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-user';

  @override
  String get displayName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeFriendshipRepo implements IFriendshipRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

final _challenge = ChallengeEntity(
  id: 'c1',
  creatorUserId: 'test-user',
  status: ChallengeStatus.completed,
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
  title: 'Corrida 10K',
);

final _result = ChallengeResultEntity(
  challengeId: 'c1',
  goal: ChallengeGoal.fastestAtDistance,
  results: const [
    ParticipantResult(
      userId: 'test-user',
      finalValue: 2400,
      rank: 1,
      outcome: ParticipantOutcome.won,
      coinsEarned: 100,
    ),
    ParticipantResult(
      userId: 'opponent',
      finalValue: 2700,
      rank: 2,
      outcome: ParticipantOutcome.lost,
      coinsEarned: 0,
    ),
  ],
  totalCoinsDistributed: 100,
  calculatedAtMs: 1700100000000,
);

final _tiedResult = ChallengeResultEntity(
  challengeId: 'c1',
  goal: ChallengeGoal.fastestAtDistance,
  results: const [
    ParticipantResult(
      userId: 'test-user',
      finalValue: 2400,
      rank: 1,
      outcome: ParticipantOutcome.tied,
      coinsEarned: 50,
    ),
    ParticipantResult(
      userId: 'opponent',
      finalValue: 2400,
      rank: 1,
      outcome: ParticipantOutcome.tied,
      coinsEarned: 50,
    ),
  ],
  totalCoinsDistributed: 100,
  calculatedAtMs: 1700100000000,
);

void main() {
  final sl = GetIt.instance;

  group('ChallengeResultScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      sl.allowReassignment = true;
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
      sl.registerFactory<IFriendshipRepo>(() => _FakeFriendshipRepo());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _result),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows victory headline when user won', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _result),
        wrapScaffold: false,
      );

      expect(find.text('Você venceu!'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsWidgets);
    });

    testWidgets('shows challenge title', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _result),
        wrapScaffold: false,
      );

      expect(find.text('Corrida 10K'), findsOneWidget);
    });

    testWidgets('shows participant results', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _result),
        wrapScaffold: false,
      );

      expect(find.text('Você'), findsWidgets);
      expect(find.text('Opponent'), findsOneWidget);
    });

    testWidgets('shows tied result', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _tiedResult),
        wrapScaffold: false,
      );

      expect(find.text('Empate!'), findsOneWidget);
    });

    testWidgets('shows CTA bar with rematch button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        ChallengeResultScreen(challenge: _challenge, result: _result),
        wrapScaffold: false,
      );

      expect(find.text('Desafiar novamente'), findsOneWidget);
      expect(find.text('Ranking'), findsOneWidget);
    });
  });
}
