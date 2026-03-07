import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/data/services/workout_delivery_service.dart';
import 'package:omni_runner/domain/repositories/i_workout_repo.dart';
import 'package:omni_runner/presentation/screens/athlete_workout_day_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWorkoutRepo implements IWorkoutRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeliveryService implements WorkoutDeliveryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AthleteWorkoutDayScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
      _sl.registerFactory<IWorkoutRepo>(() => _FakeWorkoutRepo());
      _sl.registerFactory<WorkoutDeliveryService>(
        () => _FakeDeliveryService(),
      );
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const AthleteWorkoutDayScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const AthleteWorkoutDayScreen(groupId: 'g1'),
        wrapScaffold: false,
      );

      expect(find.text('Meu Treino do Dia'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
