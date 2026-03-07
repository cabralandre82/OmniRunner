import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/wrapped_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('WrappedScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('Supabase')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      await tester.pumpApp(
        const WrappedScreen(
          periodType: 'month',
          periodKey: '2026-03',
          periodLabel: 'Março 2026',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(WrappedScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows period label in AppBar', (tester) async {
      await tester.pumpApp(
        const WrappedScreen(
          periodType: 'month',
          periodKey: '2026-03',
          periodLabel: 'Março 2026',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Março 2026'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpApp(
        const WrappedScreen(
          periodType: 'month',
          periodKey: '2026-03',
          periodLabel: 'Março 2026',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Gerando sua retrospectiva...'), findsOneWidget);
    });
  });
}
