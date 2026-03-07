import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/presentation/screens/onboarding_role_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('OnboardingRoleScreen', () {
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
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.byType(OnboardingRoleScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows role selection question', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      expect(
        find.textContaining('Como você quer usar'),
        findsOneWidget,
      );
    });

    testWidgets('shows both role options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.text('Sou atleta'), findsOneWidget);
      expect(find.text('Represento uma assessoria'), findsOneWidget);
    });

    testWidgets('continue button is disabled initially', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('selecting athlete enables continue', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      await tester.tap(find.text('Sou atleta'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows back button when onBack provided', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
          onBack: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('has athlete and staff icons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        OnboardingRoleScreen(
          initialState: OnboardingState.newUser,
          onComplete: () {},
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    });
  });
}
