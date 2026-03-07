import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_retention_dashboard_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaffRetentionDashboardScreen', () {
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
        const StaffRetentionDashboardScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffRetentionDashboardScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Retenção'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows error state when Supabase is unavailable',
        (tester) async {
      await tester.pumpApp(
        const StaffRetentionDashboardScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Não foi possível carregar os dados.'), findsOneWidget);
    });

    testWidgets('shows retry button on error', (tester) async {
      await tester.pumpApp(
        const StaffRetentionDashboardScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsWidgets);
    });
  });
}
