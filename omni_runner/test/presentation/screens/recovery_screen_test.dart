import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/usecases/recover_active_session.dart';
import 'package:omni_runner/presentation/screens/recovery_screen.dart';

import '../../helpers/pump_app.dart';

final _session = WorkoutSessionEntity(
  id: 'sess-1',
  userId: 'u-1',
  status: WorkoutStatus.running,
  startTimeMs: DateTime(2026, 3, 1, 8, 0).millisecondsSinceEpoch,
  endTimeMs: DateTime(2026, 3, 1, 8, 30).millisecondsSinceEpoch,
  totalDistanceM: 5000,
  route: const [],
);

const _metrics = WorkoutMetricsEntity(
  totalDistanceM: 5000,
  elapsedMs: 1800000,
  movingMs: 1750000,
  currentPaceSecPerKm: 360.0,
  avgPaceSecPerKm: 360.0,
  pointsCount: 200,
);

final _recovery = RecoveredSession(
  session: _session,
  rawPoints: const <LocationPointEntity>[],
  filteredPoints: const <LocationPointEntity>[],
  metrics: _metrics,
);

void main() {
  group('RecoveryScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash and has AppBar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () {},
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.byType(RecoveryScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows session detected message', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () {},
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.text('Sessão anterior detectada'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows summary card with distance', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () {},
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.text('5.00 km'), findsOneWidget);
      expect(find.text('Pontos GPS'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
    });

    testWidgets('shows resume and discard buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () {},
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.text('Salvar e continuar'), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('onResume fires when save button tapped', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var resumed = false;
      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () => resumed = true,
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      await tester.tap(find.text('Salvar e continuar'));
      expect(resumed, isTrue);
    });

    testWidgets('shows running status text for active session', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        RecoveryScreen(
          recovery: _recovery,
          onResume: () {},
          onDiscard: () {},
        ),
        wrapScaffold: false,
      );

      expect(
        find.text('Uma corrida estava em andamento quando o app fechou.'),
        findsOneWidget,
      );
    });
  });
}
