import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_bloc.dart';
import 'package:omni_runner/presentation/blocs/leaderboards/leaderboards_state.dart';
import 'package:omni_runner/presentation/screens/leaderboards_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

class _FakeLeaderboardsBloc extends Cubit<LeaderboardsState>
    implements LeaderboardsBloc {
  _FakeLeaderboardsBloc(super.initial);

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

const _leaderboard = LeaderboardEntity(
  id: 'lb1',
  scope: LeaderboardScope.global,
  period: LeaderboardPeriod.weekly,
  metric: LeaderboardMetric.composite,
  periodKey: '2026-W10',
  entries: [
    LeaderboardEntryEntity(
      userId: 'u1',
      displayName: 'Runner Alpha',
      level: 5,
      value: 42000,
      rank: 1,
      periodKey: '2026-W10',
    ),
    LeaderboardEntryEntity(
      userId: 'test-user',
      displayName: 'Test User',
      level: 3,
      value: 35000,
      rank: 2,
      periodKey: '2026-W10',
    ),
    LeaderboardEntryEntity(
      userId: 'u3',
      displayName: 'Runner Gamma',
      level: 2,
      value: 28000,
      rank: 3,
      periodKey: '2026-W10',
    ),
  ],
  computedAtMs: 1700000000000,
);

const _emptyLeaderboard = LeaderboardEntity(
  id: 'lb_empty',
  scope: LeaderboardScope.global,
  period: LeaderboardPeriod.weekly,
  metric: LeaderboardMetric.composite,
  periodKey: '2026-W10',
  entries: [],
  computedAtMs: 1700000000000,
);

void main() {
  final sl = GetIt.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => <String, Object>{},
    );
    try {
      await Supabase.initialize(
        url: 'https://fake.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZha2UiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.fake',
      );
    } catch (_) {}
  });

  group('LeaderboardsScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      sl.allowReassignment = true;
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      final bloc = _FakeLeaderboardsBloc(const LeaderboardsInitial());

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      // Consume async errors from Supabase calls in _loadUserContext
      await tester.pump();
      tester.takeException();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows loading indicator for LeaderboardsLoading state',
        (tester) async {
      final bloc = _FakeLeaderboardsBloc(const LeaderboardsLoading());

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for LeaderboardsError state',
        (tester) async {
      final bloc = _FakeLeaderboardsBloc(
        const LeaderboardsError('Erro ao carregar ranking'),
      );

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.text('Erro ao carregar ranking'), findsOneWidget);
    });

    testWidgets('shows empty state when leaderboard has no entries',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeLeaderboardsBloc(
        const LeaderboardsLoaded(leaderboard: _emptyLeaderboard),
      );

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.text('Sem assessoria'), findsOneWidget);
    });

    testWidgets('shows loaded leaderboard with entries', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeLeaderboardsBloc(
        const LeaderboardsLoaded(leaderboard: _leaderboard),
      );

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.text('Runner Alpha'), findsOneWidget);
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('Runner Gamma'), findsOneWidget);
    });

    testWidgets('shows tab bar with Assessoria, Campeonato, Global',
        (tester) async {
      final bloc = _FakeLeaderboardsBloc(const LeaderboardsInitial());

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.text('Assessoria'), findsOneWidget);
      expect(find.text('Campeonato'), findsOneWidget);
      expect(find.text('Global'), findsOneWidget);
    });

    testWidgets('shows refresh button in app bar', (tester) async {
      final bloc = _FakeLeaderboardsBloc(const LeaderboardsInitial());

      await tester.pumpApp(
        BlocProvider<LeaderboardsBloc>.value(
          value: bloc,
          child: const LeaderboardsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();
      tester.takeException();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
