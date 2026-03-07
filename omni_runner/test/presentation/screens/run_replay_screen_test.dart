import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/screens/run_replay_screen.dart';

import '../../helpers/pump_app.dart';

final _points = List.generate(
  20,
  (i) => LocationPointEntity(
    lat: -23.55 + i * 0.001,
    lng: -46.63 + i * 0.001,
    speed: 3.0,
    timestampMs: 1000 + i * 30000,
  ),
);

void main() {
  group('RunReplayScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        if (msg.contains('MissingPluginException')) return;
        if (msg.contains('PlatformException')) return;
        origOnError?.call(details);
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        (call) async => null,
      );
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/maplibre_gl'),
        null,
      );
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        RunReplayScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 600000,
        ),
        wrapScaffold: false,
      );

      expect(find.byType(RunReplayScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows replay title', (tester) async {
      await tester.pumpApp(
        RunReplayScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 600000,
        ),
        wrapScaffold: false,
      );

      expect(find.text('Replay da Corrida'), findsOneWidget);
    });

    testWidgets('shows close button', (tester) async {
      await tester.pumpApp(
        RunReplayScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 600000,
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('shows play button', (tester) async {
      await tester.pumpApp(
        RunReplayScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 600000,
        ),
        wrapScaffold: false,
      );

      expect(find.text('Reproduzir'), findsOneWidget);
    });
  });
}
