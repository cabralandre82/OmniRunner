import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('JoinAssessoriaScreen', () {
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
        JoinAssessoriaScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows search heading', (tester) async {
      await tester.pumpApp(
        JoinAssessoriaScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.textContaining('Encontre sua'), findsOneWidget);
    });

    testWidgets('shows search field', (tester) async {
      await tester.pumpApp(
        JoinAssessoriaScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('shows skip option', (tester) async {
      await tester.pumpApp(
        JoinAssessoriaScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Pular — posso entrar depois'), findsOneWidget);
    });
  });
}
