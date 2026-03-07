import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_challenge_invites_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaffChallengeInvitesScreen', () {
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
        const StaffChallengeInvitesScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffChallengeInvitesScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Desafios Recebidos'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows error state when backend unavailable', (tester) async {
      await tester.pumpApp(
        const StaffChallengeInvitesScreen(groupId: 'g1'),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Backend indisponível'), findsOneWidget);
    });
  });
}
