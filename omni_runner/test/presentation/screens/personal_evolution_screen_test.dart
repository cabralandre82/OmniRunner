import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/personal_evolution_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('PersonalEvolutionScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('Supabase')) return;
        if (msg.contains('GetIt')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      await tester.pumpApp(
        const PersonalEvolutionScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(PersonalEvolutionScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpApp(
        const PersonalEvolutionScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
