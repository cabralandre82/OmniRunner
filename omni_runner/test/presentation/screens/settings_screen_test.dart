import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http; // for StravaHttpClient stub
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/coach_settings_entity.dart';
import 'package:omni_runner/domain/repositories/i_coach_settings_repo.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/screens/settings_screen.dart';

import '../../helpers/pump_app.dart';

// ─── Stubs ───────────────────────────────────────────────────────────────────

class _StubAuthRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  AuthUser? get currentUser => const AuthUser(
        id: 'test-uid',
        email: 'test@test.com',
        displayName: 'TestUser',
        isAnonymous: false,
      );
}

class _StubCoachSettingsRepo implements ICoachSettingsRepo {
  final bool shouldThrow;

  _StubCoachSettingsRepo({this.shouldThrow = false});

  @override
  Future<CoachSettingsEntity> load() async {
    if (shouldThrow) throw Exception('Load failed');
    return const CoachSettingsEntity();
  }

  @override
  Future<void> save(CoachSettingsEntity settings) async {}
}

class _StubStravaAuthRepo implements IStravaAuthRepository {
  @override
  Future<StravaAuthState> getAuthState() async => const StravaDisconnected();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubStravaUploadRepo implements IStravaUploadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StravaConnectController _createStubStravaController() {
  return StravaConnectController(
    authRepo: _StubStravaAuthRepo(),
    uploadRepo: _StubStravaUploadRepo(),
    store: const StravaSecureStore(),
    httpClient: StravaHttpClient(client: http.Client()),
  );
}

void main() {
  group('SettingsScreen', () {
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

    void registerDeps({bool settingsThrow = false}) {
      final authRepo = _StubAuthRepo();
      sl.registerSingleton<ICoachSettingsRepo>(
        _StubCoachSettingsRepo(shouldThrow: settingsThrow),
      );
      sl.registerSingleton<StravaConnectController>(
        _createStubStravaController(),
      );
      sl.registerSingleton<UserIdentityProvider>(
        UserIdentityProvider(authRepo: authRepo),
      );
    }

    testWidgets('renders without crash', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('settles after load without crash', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shows app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows appearance section when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Aparência'), findsOneWidget);
    });

    testWidgets('shows theme mode radio buttons when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    });

    testWidgets('shows integrations section for athlete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(isStaff: false),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Integrações'), findsOneWidget);
    });

    testWidgets('hides integrations for staff', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(isStaff: true),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Integrações'), findsNothing);
    });

    testWidgets('shows privacy section for athlete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(isStaff: false),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacidade'), findsOneWidget);
    });

    testWidgets('shows units section for athlete', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const SettingsScreen(isStaff: false),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Unidades'), findsOneWidget);
    });
  });
}
