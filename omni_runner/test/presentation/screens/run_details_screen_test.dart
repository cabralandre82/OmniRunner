import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/presentation/screens/run_details_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

class _FakePointsRepo implements IPointsRepo {
  @override
  Future<List<LocationPointEntity>> getBySessionId(String sessionId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _session = WorkoutSessionEntity(
  id: 'sess-1',
  userId: 'u-1',
  status: WorkoutStatus.completed,
  startTimeMs: DateTime(2026, 3, 1, 8, 0).millisecondsSinceEpoch,
  endTimeMs: DateTime(2026, 3, 1, 8, 30).millisecondsSinceEpoch,
  totalDistanceM: 5000,
  route: const [],
);

void main() {
  group('RunDetailsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('MissingPluginException')) return;
        if (msg.contains('PlatformException')) return;
        if (msg.contains('Supabase')) return;
        origOnError?.call(details);
      };

      final sl = GetIt.instance;
      if (!sl.isRegistered<IPointsRepo>()) {
        sl.registerSingleton<IPointsRepo>(_FakePointsRepo());
      }

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        (call) async => null,
      );
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      GetIt.instance.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        null,
      );
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        RunDetailsScreen(session: _session),
        wrapScaffold: false,
      );

      expect(find.byType(RunDetailsScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows back button', (tester) async {
      await tester.pumpApp(
        RunDetailsScreen(session: _session),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows export button', (tester) async {
      await tester.pumpApp(
        RunDetailsScreen(session: _session),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
    });
  });
}
