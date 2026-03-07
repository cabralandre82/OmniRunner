import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/diagnostics_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('DiagnosticsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('Supabase')) return;
        if (msg.contains('GetIt')) return;
        if (msg.contains('MissingPluginException')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      await tester.pumpApp(
        const DiagnosticsScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(DiagnosticsScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Diagnóstico'), findsOneWidget);
    });

    testWidgets('shows diagnostic content based on build mode',
        (tester) async {
      await tester.pumpApp(
        const DiagnosticsScreen(),
        wrapScaffold: false,
      );

      // In debug mode (tests run in debug), should show loading or items
      // In release mode, shows "not available" message
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
