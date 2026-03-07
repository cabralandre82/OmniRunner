import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/map_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('MapScreen', () {
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

    testWidgets('renders without crash and has AppBar', (tester) async {
      await tester.pumpApp(
        const MapScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Mapa'), findsOneWidget);
    });

    testWidgets('shows loading indicator while map loads', (tester) async {
      await tester.pumpApp(
        const MapScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
