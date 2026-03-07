import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';

import '../../helpers/pump_app.dart';

// ─── Stubs ───────────────────────────────────────────────────────────────────

class _StubSessionRepo implements ISessionRepo {
  final List<WorkoutSessionEntity> sessions;

  _StubSessionRepo({this.sessions = const []});

  @override
  Future<List<WorkoutSessionEntity>> getAll() async => sessions;

  @override
  Future<WorkoutSessionEntity?> getById(String id) async => null;

  @override
  Future<void> save(WorkoutSessionEntity session) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSyncRepo implements ISyncRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _session1 = WorkoutSessionEntity(
  id: 's1',
  userId: 'u1',
  status: WorkoutStatus.completed,
  startTimeMs: DateTime(2026, 3, 1, 8).millisecondsSinceEpoch,
  endTimeMs: DateTime(2026, 3, 1, 9).millisecondsSinceEpoch,
  totalDistanceM: 5200,
  route: const [],
  isVerified: true,
  integrityFlags: const [],
  isSynced: true,
  source: 'app',
);

final _session2 = WorkoutSessionEntity(
  id: 's2',
  userId: 'u1',
  status: WorkoutStatus.completed,
  startTimeMs: DateTime(2026, 2, 28, 7).millisecondsSinceEpoch,
  endTimeMs: DateTime(2026, 2, 28, 7, 45).millisecondsSinceEpoch,
  totalDistanceM: 3100,
  route: const [],
  isVerified: true,
  integrityFlags: const [],
  isSynced: false,
  source: 'strava',
  deviceName: 'Garmin 265',
);

void main() {
  group('HistoryScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    void registerDeps({List<WorkoutSessionEntity> sessions = const []}) {
      sl.registerSingleton<ISessionRepo>(
        _StubSessionRepo(sessions: sessions),
      );
      sl.registerSingleton<ISyncRepo>(_StubSyncRepo());
    }

    testWidgets('renders without crash', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('shows app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loading initially', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('shows empty state when no sessions', (tester) async {
      registerDeps(sessions: []);

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text('Nenhuma corrida ainda'), findsOneWidget);
    });

    testWidgets('shows sessions when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps(sessions: [_session1, _session2]);

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('5.20 km'), findsOneWidget);
    });

    testWidgets('shows sync button in app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const HistoryScreen(),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('shows ghost picker title when pickGhostMode', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const HistoryScreen(pickGhostMode: true),
        wrapScaffold: false,
      );

      expect(find.text('Escolher fantasma'), findsOneWidget);
    });
  });
}
