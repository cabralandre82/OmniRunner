import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/challenge_join_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('ChallengeJoinScreen', () {
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
      await tester.pumpApp(
        const ChallengeJoinScreen(challengeId: 'test-challenge-id'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const ChallengeJoinScreen(challengeId: 'test-challenge-id'),
        wrapScaffold: false,
      );

      expect(find.text('Convite de Desafio'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows error state after failed load', (tester) async {
      await tester.pumpApp(
        const ChallengeJoinScreen(challengeId: 'test-challenge-id'),
        wrapScaffold: false,
      );

      // The Supabase call will fail (not initialized in test).
      // The catch block sets error state. Pump to let the Future complete.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Não foi possível carregar o desafio.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('shows retry button on error state', (tester) async {
      await tester.pumpApp(
        const ChallengeJoinScreen(challengeId: 'test-challenge-id'),
        wrapScaffold: false,
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Tentar novamente'), findsOneWidget);
    });
  });
}
