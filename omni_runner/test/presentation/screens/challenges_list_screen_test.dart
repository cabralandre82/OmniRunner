import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/screens/challenges_list_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeChallengesBloc extends Cubit<ChallengesState>
    implements ChallengesBloc {
  _FakeChallengesBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeStravaAuthRepo implements IStravaAuthRepository {
  @override
  Future<StravaAuthState> getAuthState() async => const StravaDisconnected();

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeStravaUploadRepo implements IStravaUploadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-user';

  @override
  String get displayName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

const _activeChallenge = ChallengeEntity(
  id: 'c1',
  creatorUserId: 'test-user',
  status: ChallengeStatus.active,
  type: ChallengeType.oneVsOne,
  rules: ChallengeRulesEntity(
    goal: ChallengeGoal.fastestAtDistance,
    windowMs: 86400000,
    entryFeeCoins: 50,
  ),
  participants: [],
  createdAtMs: 1700000000000,
  title: 'Desafio 5K',
);

const _completedChallenge = ChallengeEntity(
  id: 'c2',
  creatorUserId: 'test-user',
  status: ChallengeStatus.completed,
  type: ChallengeType.group,
  rules: ChallengeRulesEntity(
    goal: ChallengeGoal.mostDistance,
    windowMs: 604800000,
    entryFeeCoins: 100,
  ),
  participants: [],
  createdAtMs: 1699000000000,
  title: 'Maratona Grupo',
);

void main() {
  final sl = GetIt.instance;

  group('ChallengesListScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      AppConfig.demoMode = false;
      sl.allowReassignment = true;
      sl.registerFactory<StravaConnectController>(
        () => StravaConnectController(
          authRepo: _FakeStravaAuthRepo(),
          uploadRepo: _FakeStravaUploadRepo(),
          store: const StravaSecureStore(),
          httpClient: StravaHttpClient(),
        ),
      );
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash in initial state', (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loading for ChallengesLoading state',
        (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesLoading());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error state for ChallengesError', (tester) async {
      final bloc =
          _FakeChallengesBloc(const ChallengesError('Falha na conexão'));

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha na conexão'), findsOneWidget);
    });

    testWidgets('shows empty state when challenges list is empty',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesLoaded([]));

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Crie seu primeiro desafio'), findsOneWidget);
    });

    testWidgets('shows loaded challenges with section headers',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(
        const ChallengesLoaded([_activeChallenge, _completedChallenge]),
      );

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Ativos'), findsOneWidget);
      expect(find.text('Concluídos'), findsOneWidget);
      expect(find.text('Desafio 5K'), findsOneWidget);
      expect(find.text('Maratona Grupo'), findsOneWidget);
    });

    testWidgets('shows demo challenges when demoMode is true',
        (tester) async {
      AppConfig.demoMode = true;

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Desafio 5K — Menor Tempo'), findsOneWidget);
    });

    testWidgets('has add button in app bar', (tester) async {
      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengesListScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
