import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/onboarding_tour_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

void main() {
  group('OnboardingTourScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      ensureSupabaseClientRegistered();
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(OnboardingTourScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows first slide content', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Importe corridas do Strava'), findsOneWidget);
    });

    testWidgets('shows skip button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Pular'), findsOneWidget);
    });

    testWidgets('shows PRÓXIMO on first page', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.text('PRÓXIMO'), findsOneWidget);
    });

    testWidgets('has PageView for slides', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('shows Strava icon on first slide', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingTourScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    });
  });
}
