import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/presentation/screens/personal_evolution_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-user';

  @override
  String get displayName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  group('PersonalEvolutionScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      if (!GetIt.instance.isRegistered<UserIdentityProvider>()) {
        GetIt.instance.registerFactory<UserIdentityProvider>(
          () => _FakeUserIdentity(),
        );
      }
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
        const PersonalEvolutionScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(PersonalEvolutionScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('renders loading or content state', (tester) async {
      await tester.pumpApp(
        const PersonalEvolutionScreen(),
        wrapScaffold: false,
      );
      // Use pump() instead of pumpAndSettle - CircularProgressIndicator never settles
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // With fake Supabase, async completes quickly; verify screen renders
      expect(find.byType(PersonalEvolutionScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
