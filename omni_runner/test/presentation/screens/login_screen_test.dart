import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/login_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('LoginScreen', () {
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
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('renders header text', (tester) async {
      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Entrar no Omni Runner'), findsOneWidget);
    });

    testWidgets('renders runner icon', (tester) async {
      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    });

    testWidgets('shows Google sign-in button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.g_mobiledata_rounded), findsOneWidget);
    });

    testWidgets('shows Apple sign-in button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.apple_rounded), findsOneWidget);
    });

    testWidgets('shows email sign-in button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });

    testWidgets('shows Instagram sign-in button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Continuar com Instagram'), findsOneWidget);
    });

    testWidgets('tapping email button shows email form', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Email'), findsNothing);

      await tester.tap(find.text('Continuar com Email'));
      await tester.pump();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
    });

    testWidgets('shows privacy policy link', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Política de Privacidade'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows invite banner when hasPendingInvite', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}, hasPendingInvite: true),
        wrapScaffold: false,
      );

      expect(find.text('Você recebeu um convite! '
          'Faça login para entrar na assessoria.'), findsOneWidget);
      expect(find.byIcon(Icons.group_add_rounded), findsOneWidget);
    });

    testWidgets('does not show invite banner by default', (tester) async {
      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.group_add_rounded), findsNothing);
    });

    testWidgets('email form shows toggle between login and signup',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        LoginScreen(onSuccess: () {}),
        wrapScaffold: false,
      );

      await tester.tap(find.text('Continuar com Email'));
      await tester.pump();

      expect(find.text('Não tem conta? Criar agora'), findsOneWidget);
    });
  });
}
