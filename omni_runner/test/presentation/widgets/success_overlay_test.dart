import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/widgets/success_overlay.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('AnimatedCheckmark', () {
    testWidgets('renders and animates', (tester) async {
      await tester.pumpApp(
        const Center(
          child: AnimatedCheckmark(size: 60, color: Colors.green),
        ),
      );

      expect(find.byType(AnimatedCheckmark), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('calls onComplete after animation', (tester) async {
      var completed = false;

      await tester.pumpApp(
        Center(
          child: AnimatedCheckmark(
            size: 60,
            onComplete: () => completed = true,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });

    testWidgets('uses specified size for container', (tester) async {
      await tester.pumpApp(
        const Center(
          child: AnimatedCheckmark(size: 100),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AnimatedCheckmark),
          matching: find.byType(Container),
        ),
      );
      expect(container.constraints?.maxWidth, 100);
      expect(container.constraints?.maxHeight, 100);
    });
  });

  group('ConfettiBurst', () {
    testWidgets('renders particles', (tester) async {
      await tester.pumpApp(
        const SizedBox(
          width: 200,
          height: 200,
          child: ConfettiBurst(particleCount: 10),
        ),
      );

      expect(find.byType(ConfettiBurst), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('is non-interactive (IgnorePointer)', (tester) async {
      await tester.pumpApp(
        const SizedBox(
          width: 200,
          height: 200,
          child: ConfettiBurst(),
        ),
      );

      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });
}
