import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/athlete_championships_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('AthleteChampionshipsScreen', () {
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

    testWidgets('shows error state when backend unavailable', (tester) async {
      await tester.pumpApp(
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );

      expect(
        find.text('Não foi possível carregar os campeonatos.'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows refresh button in error state', (tester) async {
      await tester.pumpApp(
        const AthleteChampionshipsScreen(),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
