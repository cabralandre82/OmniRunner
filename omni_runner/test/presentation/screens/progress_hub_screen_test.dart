import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/progress_hub_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('ProgressHubScreen', () {
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
        const ProgressHubScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const ProgressHubScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Progressão'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows section headers', (tester) async {
      await tester.pumpApp(
        const ProgressHubScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Progresso'), findsOneWidget);
      expect(find.text('Conquistas'), findsOneWidget);
    });

    testWidgets('shows navigation tiles', (tester) async {
      await tester.pumpApp(
        const ProgressHubScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Nível e XP'), findsOneWidget);
      expect(find.text('Badges'), findsOneWidget);
    });
  });
}
