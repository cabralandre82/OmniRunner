import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/presentation/screens/run_summary_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

final _points = [
  LocationPointEntity(lat: -23.55, lng: -46.63, timestampMs: 1000),
  LocationPointEntity(lat: -23.551, lng: -46.631, timestampMs: 2000),
  LocationPointEntity(lat: -23.552, lng: -46.632, timestampMs: 3000),
];

void main() {
  group('RunSummaryScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
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
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
          avgPaceSecPerKm: 360,
        ),
        wrapScaffold: false,
      );

      expect(find.byType(RunSummaryScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows title text', (tester) async {
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      expect(find.text('Resumo da Corrida'), findsOneWidget);
    });

    testWidgets('shows close button', (tester) async {
      await tester.pumpApp(
        RunSummaryScreen(
          points: _points,
          totalDistanceM: 5000,
          elapsedMs: 1800000,
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
