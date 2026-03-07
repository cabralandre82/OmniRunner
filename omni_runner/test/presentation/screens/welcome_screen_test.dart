import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/welcome_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('WelcomeScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        WelcomeScreen(onStart: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows hero text and CTA button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        WelcomeScreen(onStart: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Seu app de corrida completo'), findsOneWidget);
      expect(find.text('COMEÇAR'), findsOneWidget);
    });

    testWidgets('shows value prop bullets', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        WelcomeScreen(onStart: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Importe corridas via Strava'), findsOneWidget);
      expect(find.text('Desafie amigos com OmniCoins'), findsOneWidget);
      expect(find.text('Descubra seu DNA de Corredor'), findsOneWidget);
      expect(find.text('Treine com sua assessoria'), findsOneWidget);
    });

    testWidgets('onStart callback fires on CTA tap', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var started = false;
      await tester.pumpApp(
        WelcomeScreen(onStart: () => started = true),
        wrapScaffold: false,
      );

      await tester.tap(find.text('COMEÇAR'));
      expect(started, isTrue);
    });

    testWidgets('shows explore button when onExplore provided', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        WelcomeScreen(onStart: () {}, onExplore: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Explorar sem conta'), findsOneWidget);
    });

    testWidgets('hides explore button when onExplore is null', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        WelcomeScreen(onStart: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Explorar sem conta'), findsNothing);
    });

    testWidgets('shows runner icon', (tester) async {
      await tester.pumpApp(
        WelcomeScreen(onStart: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    });
  });
}
