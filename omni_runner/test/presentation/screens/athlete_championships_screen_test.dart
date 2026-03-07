import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('AthleteChampionshipsScreen', () {
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
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      await tester.pumpApp(
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Campeonatos'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows empty state when no championships', (tester) async {
      await tester.pumpApp(
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum campeonato disponível'),
        findsOneWidget,
      );
    });

    testWidgets('shows empty state message when no championships', (tester) async {
      await tester.pumpApp(
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Quando sua assessoria'),
        findsOneWidget,
      );
    });
  });
}
