import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/league_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('LeagueScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const LeagueScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const LeagueScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Liga de Assessorias'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows empty state when no active season', (tester) async {
      await tester.pumpApp(
        const LeagueScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma temporada ativa'), findsOneWidget);
    });
  });
}
