import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/router/app_router.dart';

/// Regression tests for go_router route ordering.
///
/// Bug: the static route `/support/ticket` was declared AFTER the
/// parameterised route `/support/:groupId`. go_router captured "ticket"
/// as the :groupId value, causing a `22P02` error in the database
/// (`invalid input syntax for type uuid: "ticket"`).
///
/// Fix: static routes must be declared before parameterised siblings that
/// share the same prefix.
void main() {
  group('AppRoutes constants', () {
    test('support routes have distinct patterns', () {
      expect(AppRoutes.support, '/support/:groupId');
      expect(AppRoutes.supportTicket, '/support/ticket');
    });

    test('supportTicket static segment is not UUID-shaped', () {
      final segment = AppRoutes.supportTicket.split('/').last;
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(
        uuidRegex.hasMatch(segment),
        isFalse,
        reason:
            '"$segment" must not be UUID-shaped. If go_router captures it as '
            ':groupId the Supabase query fails with 22P02.',
      );
    });
  });

  group('Route ordering — static before parameterised', () {
    late GoRouter router;

    setUp(() {
      // Build a minimal router with only the two conflicting routes,
      // in the CORRECT order (static first).
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const SizedBox()),
          // Correct order: static before parameterised.
          GoRoute(
            path: AppRoutes.supportTicket, // '/support/ticket'
            builder: (_, __) => const Text('ticket-screen'),
          ),
          GoRoute(
            path: AppRoutes.support, // '/support/:groupId'
            builder: (context, state) =>
                Text('support-${state.pathParameters['groupId']}'),
          ),
        ],
      );
    });

    tearDown(() => router.dispose());

    testWidgets('navigating to /support/ticket hits the ticket route',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go(AppRoutes.supportTicket);
      await tester.pumpAndSettle();

      expect(find.text('ticket-screen'), findsOneWidget);
      expect(find.textContaining('support-ticket'), findsNothing);
    });

    testWidgets('navigating to /support/<uuid> hits the support route',
        (tester) async {
      const fakeUuid = '34747023-6a87-48e3-a93f-60e0ab04e411';
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      router.go('/support/$fakeUuid');
      await tester.pumpAndSettle();

      expect(find.text('support-$fakeUuid'), findsOneWidget);
      expect(find.text('ticket-screen'), findsNothing);
    });
  });
}
