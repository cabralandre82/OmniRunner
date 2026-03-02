import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/invalidated_run_card.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('InvalidatedRunCard', () {
    testWidgets('shows title and friendly reasons', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: ['SPEED_IMPOSSIBLE', 'GPS_JUMP'],
          ),
        ),
      );

      expect(
        find.text('Não conseguimos validar esta atividade'),
        findsOneWidget,
      );
      expect(
        find.text('Velocidade GPS acima do esperado para corrida'),
        findsOneWidget,
      );
      expect(
        find.text('Salto de posição GPS detectado (sinal instável)'),
        findsOneWidget,
      );
    });

    testWidgets('shows fallback message for unknown flags', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: ['UNKNOWN_FLAG_XYZ'],
          ),
        ),
      );

      expect(
        find.text('Dados inconsistentes detectados'),
        findsOneWidget,
      );
    });

    testWidgets('deduplicates reasons for legacy flags', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: ['HIGH_SPEED', 'SPEED_EXCEEDED', 'SPEED_IMPOSSIBLE'],
          ),
        ),
      );

      expect(
        find.text('Velocidade GPS acima do esperado para corrida'),
        findsOneWidget,
      );
    });

    testWidgets('shows retry button when onRetry is set', (tester) async {
      var retried = false;

      await tester.pumpApp(
        SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: const ['GPS_JUMP'],
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: ['GPS_JUMP'],
          ),
        ),
      );

      expect(find.text('Tentar novamente'), findsNothing);
    });

    testWidgets('shows review button when coachingGroupId and onRequestReview are set',
        (tester) async {
      var reviewed = false;

      await tester.pumpApp(
        SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: const ['GPS_JUMP'],
            coachingGroupId: 'group-1',
            onRequestReview: () => reviewed = true,
          ),
        ),
      );

      expect(find.text('Enviar para revisão'), findsOneWidget);
      await tester.tap(find.text('Enviar para revisão'));
      expect(reviewed, isTrue);
    });

    testWidgets('always shows GPS tips button', (tester) async {
      await tester.pumpApp(
        const SingleChildScrollView(
          child: InvalidatedRunCard(
            integrityFlags: ['TOO_FEW_POINTS'],
          ),
        ),
      );

      expect(find.text('Ver dicas de GPS'), findsOneWidget);
    });
  });
}
