import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/dispute_status_card.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('DisputeStatusCard', () {
    testWidgets('renders pendingClearing phase', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.pendingClearing),
        ),
      );

      expect(
        find.text('Aguardando confirmação entre assessorias'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    });

    testWidgets('renders sentConfirmed phase', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.sentConfirmed),
        ),
      );

      expect(
        find.text('Envio confirmado — aguardando recebimento'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('renders disputed phase', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.disputed),
        ),
      );

      expect(find.text('Em análise pelas assessorias'), findsOneWidget);
    });

    testWidgets('renders cleared phase with success icon', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.cleared),
        ),
      );

      expect(find.text('Prêmio liberado!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('renders expired phase', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.expired),
        ),
      );

      expect(find.text('Prazo encerrado'), findsOneWidget);
    });

    testWidgets('shows coins when coinsAmount is set', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(
            phase: DisputePhase.cleared,
            coinsAmount: 150,
          ),
        ),
      );

      expect(find.text('150 OmniCoins'), findsOneWidget);
    });

    testWidgets('hides coins row when coinsAmount is null', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: DisputeStatusCard(phase: DisputePhase.pendingClearing),
        ),
      );

      expect(find.byIcon(Icons.toll_rounded), findsNothing);
    });

    testWidgets('shows deadline for non-cleared phases', (tester) async {
      final future = DateTime.now().add(const Duration(days: 3));

      await tester.pumpApp(
        SingleChildScrollView(
          child: DisputeStatusCard(
            phase: DisputePhase.pendingClearing,
            deadlineAt: future,
          ),
        ),
      );

      expect(find.textContaining('dias'), findsOneWidget);
    });

    testWidgets('hides deadline for cleared phase', (tester) async {
      await tester.pumpApp(
        SingleChildScrollView(
          child: DisputeStatusCard(
            phase: DisputePhase.cleared,
            deadlineAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ),
      );

      expect(find.textContaining('Prazo'), findsNothing);
    });
  });
}
