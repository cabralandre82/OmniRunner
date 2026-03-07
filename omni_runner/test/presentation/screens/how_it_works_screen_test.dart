import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/how_it_works_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('HowItWorksScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const HowItWorksScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(HowItWorksScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Como Funciona'), findsOneWidget);
    });

    testWidgets('shows all four sections', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const HowItWorksScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Desafios'), findsOneWidget);
      expect(find.text('OmniCoins'), findsOneWidget);
      expect(find.text('Verificação'), findsOneWidget);
      expect(find.text('Integridade das Corridas'), findsOneWidget);
    });

    testWidgets('shows info cards with content', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const HowItWorksScreen(),
        wrapScaffold: false,
      );

      expect(find.text('O que são?'), findsOneWidget);
      expect(find.text('De onde vêm?'), findsOneWidget);
    });

    testWidgets('has section icons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const HowItWorksScreen(),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    });
  });
}
