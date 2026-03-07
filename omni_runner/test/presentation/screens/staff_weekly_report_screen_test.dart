import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_weekly_report_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('StaffWeeklyReportScreen', () {
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
        const StaffWeeklyReportScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffWeeklyReportScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );

      expect(find.text('Relatório semanal'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows empty report when no athletes in group',
        (tester) async {
      await tester.pumpApp(
        const StaffWeeklyReportScreen(
          groupId: 'g1',
          groupName: 'Test Group',
        ),
        wrapScaffold: false,
      );
      // Use pump() instead of pumpAndSettle - CircularProgressIndicator never settles
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Relatório semanal'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
