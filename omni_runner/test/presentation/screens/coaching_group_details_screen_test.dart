import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/coaching_group_details_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('CoachingGroupDetailsScreen', () {
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

    testWidgets('renders scaffold with app bar', (tester) async {
      await tester.pumpApp(
        const CoachingGroupDetailsScreen(
          groupId: 'test-group',
          callerUserId: 'test-user',
        ),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Atletas e Staff'), findsOneWidget);
    });

    testWidgets('shows error state when group not found', (tester) async {
      await tester.pumpApp(
        const CoachingGroupDetailsScreen(
          groupId: 'g1',
          callerUserId: 'u1',
        ),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Assessoria não encontrada'), findsOneWidget);
    });
  });
}
