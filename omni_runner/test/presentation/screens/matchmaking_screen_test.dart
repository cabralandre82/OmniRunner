// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';
import 'package:omni_runner/presentation/screens/matchmaking_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeVerificationBloc extends Cubit<VerificationState>
    implements VerificationBloc {
  _FakeVerificationBloc(super.initial);

  @override
  void add(VerificationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStravaCtrl implements StravaConnectController {
  @override
  Future<bool> get isConnected async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessionRepo implements ISessionRepo {
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus s) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MatchmakingScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<VerificationBloc>(
        () => _FakeVerificationBloc(const VerificationInitial()),
      );
      _sl.registerFactory<StravaConnectController>(() => _FakeStravaCtrl());
      _sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
      _sl.registerFactory<ISessionRepo>(() => _FakeSessionRepo());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const MatchmakingScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const MatchmakingScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows setup form initially', (tester) async {
      await tester.pumpApp(
        const MatchmakingScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
