import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/empty_state.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpApp(
        const EmptyState(
          icon: Icons.inbox,
          title: 'Nada aqui',
          subtitle: 'Volte mais tarde',
        ),
      );

      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('Nada aqui'), findsOneWidget);
      expect(find.text('Volte mais tarde'), findsOneWidget);
    });

    testWidgets('does not show button when actionLabel is null', (tester) async {
      await tester.pumpApp(
        const EmptyState(
          icon: Icons.inbox,
          title: 'Vazio',
          subtitle: 'Sem dados',
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows CTA button when actionLabel and onAction are set',
        (tester) async {
      var tapped = false;

      await tester.pumpApp(
        EmptyState(
          icon: Icons.add,
          title: 'Vazio',
          subtitle: 'Crie algo',
          actionLabel: 'Criar',
          onAction: () => tapped = true,
        ),
      );

      expect(find.text('Criar'), findsOneWidget);
      await tester.tap(find.text('Criar'));
      expect(tapped, isTrue);
    });

    testWidgets('has Semantics widget wrapping content', (tester) async {
      await tester.pumpApp(
        const EmptyState(
          icon: Icons.inbox,
          title: 'Título',
          subtitle: 'Subtítulo',
        ),
      );

      expect(find.byType(Semantics), findsWidgets);
      expect(find.text('Título'), findsOneWidget);
      expect(find.text('Subtítulo'), findsOneWidget);
    });
  });
}
