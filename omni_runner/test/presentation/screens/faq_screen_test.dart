import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/faq_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('FaqScreen', () {
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
        const FaqScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(FaqScreen), findsOneWidget);
    });

    testWidgets('renders app bar with title', (tester) async {
      await tester.pumpApp(
        const FaqScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Perguntas Frequentes'), findsOneWidget);
    });

    testWidgets('shows athlete FAQs by default', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const FaqScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Como sincronizar meu relógio?'), findsOneWidget);
      expect(find.text('Como entrar em uma assessoria?'), findsOneWidget);
      expect(find.text('Como funcionam os OmniCoins?'), findsOneWidget);
      expect(find.text('Como verificar meu perfil?'), findsOneWidget);
      expect(find.text('Como reportar um problema?'), findsOneWidget);
    });

    testWidgets('shows staff FAQs when isStaff is true', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const FaqScreen(isStaff: true),
        wrapScaffold: false,
      );

      expect(
        find.text('Como convidar atletas para minha assessoria?'),
        findsOneWidget,
      );
      expect(find.text('Como distribuir OmniCoins?'), findsOneWidget);
      expect(find.text('Como criar campeonatos?'), findsOneWidget);
    });

    testWidgets('FAQ items are expandable', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const FaqScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(ExpansionTile), findsWidgets);
    });

    testWidgets('tapping FAQ item expands answer', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const FaqScreen(),
        wrapScaffold: false,
      );

      await tester.tap(find.text('Como sincronizar meu relógio?'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Conecte o Strava na tela de configurações'),
        findsOneWidget,
      );
    });

    testWidgets('uses Card widgets for FAQ items', (tester) async {
      await tester.pumpApp(
        const FaqScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('staff FAQs do not show athlete questions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const FaqScreen(isStaff: true),
        wrapScaffold: false,
      );

      expect(find.text('Como sincronizar meu relógio?'), findsNothing);
      expect(find.text('Como entrar em uma assessoria?'), findsNothing);
    });
  });
}
