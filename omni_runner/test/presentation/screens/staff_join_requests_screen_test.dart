import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_join_requests_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaffJoinRequestsScreen', () {
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
        const StaffJoinRequestsScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffJoinRequestsScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Solicitações de Entrada'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows error state when Supabase unavailable',
        (tester) async {
      await tester.pumpApp(
        const StaffJoinRequestsScreen(groupId: 'g1'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar as solicitações.'),
        findsOneWidget,
      );
    });

    testWidgets('shows retry button on error', (tester) async {
      await tester.pumpApp(
        const StaffJoinRequestsScreen(groupId: 'g1'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Tentar novamente'), findsOneWidget);
    });
  });
}
