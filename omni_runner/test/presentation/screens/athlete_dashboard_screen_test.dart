import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/presentation/screens/athlete_dashboard_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('AthleteDashboardScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      AppConfig.demoMode = true;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() {
      AppConfig.demoMode = false;
      FlutterError.onError = origOnError;
    });

    testWidgets('renders without crash in demo mode', (tester) async {
      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Omni Runner'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows greeting with demo name', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Olá, Explorador!'), findsOneWidget);
    });

    testWidgets('shows question prompt in loaded state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('O que deseja fazer hoje?'), findsOneWidget);
    });

    testWidgets('shows dashboard cards in loaded state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Meus desafios'), findsOneWidget);
      expect(find.text('Meu progresso'), findsOneWidget);
    });

    testWidgets('shows join assessoria card when not bound', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const AthleteDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Entrar em assessoria'), findsOneWidget);
    });
  });
}
