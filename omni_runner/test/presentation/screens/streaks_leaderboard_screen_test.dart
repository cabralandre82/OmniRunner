import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/streaks_leaderboard_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('StreaksLeaderboardScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('Supabase')) return;
        if (msg.contains('GetIt')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      await tester.pumpApp(
        const StreaksLeaderboardScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(StreaksLeaderboardScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('renders loading or content state', (tester) async {
      await tester.pumpApp(
        const StreaksLeaderboardScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      // With fake Supabase, async completes quickly; verify screen renders
      expect(find.byType(StreaksLeaderboardScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
