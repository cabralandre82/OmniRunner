import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/presentation/screens/workout_delivery_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WorkoutDeliveryScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const WorkoutDeliveryScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const WorkoutDeliveryScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Meus Treinos Entregues'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
