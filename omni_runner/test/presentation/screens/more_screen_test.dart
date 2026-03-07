import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/screens/more_screen.dart';

import '../../helpers/pump_app.dart';

// ─── Stubs ───────────────────────────────────────────────────────────────────

class _StubAuthRepo implements AuthRepository {
  final bool anonymous;

  _StubAuthRepo({this.anonymous = false});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  AuthUser? get currentUser => AuthUser(
        id: 'test-uid',
        email: anonymous ? null : 'test@test.com',
        displayName: 'TestUser',
        isAnonymous: anonymous,
      );
}

void main() {
  group('MoreScreen', () {
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

    void registerDeps({bool anonymous = false}) {
      final authRepo = _StubAuthRepo(anonymous: anonymous);
      final identity = UserIdentityProvider(authRepo: authRepo);
      // Simulate init by refreshing the cached user
      identity.refresh();
      sl.registerSingleton<UserIdentityProvider>(identity);
      sl.registerSingleton<AuthRepository>(authRepo);
    }

    testWidgets('renders without crash for athlete', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('shows app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows account section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.text('Conta'), findsOneWidget);
      expect(find.text('Meu Perfil'), findsOneWidget);
    });

    testWidgets('shows social section for athlete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.text('Social'), findsOneWidget);
      expect(find.text('Convidar amigos'), findsOneWidget);
      expect(find.text('Meus Amigos'), findsOneWidget);
    });

    testWidgets('shows treinos section for athlete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.text('Treinos'), findsOneWidget);
      expect(find.text('Escanear QR'), findsOneWidget);
    });

    testWidgets('shows help section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.text('Ajuda'), findsOneWidget);
      expect(find.text('Perguntas Frequentes'), findsOneWidget);
    });

    testWidgets('shows logout button for authenticated user', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps(anonymous: false);

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('shows offline mode card for anonymous user', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps(anonymous: true);

      await tester.pumpApp(
        const MoreScreen(userRole: 'ATLETA'),
        wrapScaffold: false,
      );

      expect(find.text('Modo Offline'), findsOneWidget);
      expect(find.text('Criar conta / Entrar'), findsOneWidget);
    });

    testWidgets('hides social section for staff', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ASSESSORIA_STAFF'),
        wrapScaffold: false,
      );

      expect(find.text('Social'), findsNothing);
    });

    testWidgets('shows assessoria section for staff', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const MoreScreen(userRole: 'ASSESSORIA_STAFF'),
        wrapScaffold: false,
      );

      expect(find.text('Operações QR'), findsOneWidget);
    });
  });
}
