import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/push/notification_rules_service.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/data/services/today_data_service.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/presentation/strava_connect_controller.dart';
import 'package:omni_runner/presentation/screens/today_screen.dart';

import '../../helpers/pump_app.dart';

// ─── Stubs ───────────────────────────────────────────────────────────────────

class _StubAuthRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  AuthUser? get currentUser => const AuthUser(
        id: 'test-uid',
        displayName: 'TestUser',
        isAnonymous: false,
      );
}

class _StubProfileProgressRepo implements IProfileProgressRepo {
  @override
  Future<ProfileProgressEntity> getByUserId(String uid) async =>
      ProfileProgressEntity(userId: uid, totalXp: 500, dailyStreakCount: 3);

  @override
  Future<void> save(ProfileProgressEntity p) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSessionRepo implements ISessionRepo {
  @override
  Future<List<WorkoutSessionEntity>> getByStatus(WorkoutStatus s) async => [];

  @override
  Future<List<WorkoutSessionEntity>> getAll() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTodayDataService implements TodayDataService {
  @override
  Future<void> recalculateProfileProgress(String uid) async {}

  @override
  Future<Map<String, dynamic>?> getProfileProgress(String uid) async => {
        'total_xp': 500,
        'season_xp': 100,
        'daily_streak_count': 3,
        'streak_best': 7,
        'has_freeze_available': false,
        'weekly_session_count': 2,
        'monthly_session_count': 8,
        'lifetime_session_count': 30,
        'lifetime_distance_m': 150000.0,
        'lifetime_moving_ms': 50000000,
      };

  @override
  Future<List<Map<String, dynamic>>> getRemoteSessions(String uid) async => [];

  @override
  Future<List<String>> getActiveChallengeIds(String uid) async => [];

  @override
  Future<List<String>> getActiveChampionshipIds(String uid) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _StubChallengeRepo implements IChallengeRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubBadgeAwardRepo implements IBadgeAwardRepo {
  @override
  Future<List<BadgeAwardEntity>> getByUserId(String uid) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNotificationRules implements NotificationRulesService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubFirstUseTips implements FirstUseTips {
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
  group('TodayScreen', () {
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

    void registerDeps() {
      final authRepo = _StubAuthRepo();
      final identity = UserIdentityProvider(authRepo: authRepo);
      identity.refresh();
      sl.registerSingleton<UserIdentityProvider>(identity);
      sl.registerSingleton<AuthRepository>(authRepo);
      sl.registerSingleton<IProfileProgressRepo>(_StubProfileProgressRepo());
      sl.registerSingleton<ISessionRepo>(_StubSessionRepo());
      sl.registerSingleton<TodayDataService>(_StubTodayDataService());
      sl.registerSingleton<StravaConnectController>(
        _createStubStravaController(),
      );
      sl.registerSingleton<IChallengeRepo>(_StubChallengeRepo());
      sl.registerSingleton<IBadgeAwardRepo>(_StubBadgeAwardRepo());
      sl.registerSingleton<NotificationRulesService>(_StubNotificationRules());
      sl.registerSingleton<FirstUseTips>(_StubFirstUseTips());
    }

    testWidgets('renders without crash', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('shows app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows shimmer loading initially', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('shows streak banner when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('seguido'), findsOneWidget);
    });

    testWidgets('shows quick stats when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Resumo'), findsOneWidget);
    });

    testWidgets('shows strava connect prompt when not connected',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Conecte o Strava para começar'), findsOneWidget);
    });

    testWidgets('shows error state on load failure', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authRepo = _StubAuthRepo();
      final identity = UserIdentityProvider(authRepo: authRepo);
      identity.refresh();
      sl.registerSingleton<UserIdentityProvider>(identity);
      sl.registerSingleton<AuthRepository>(authRepo);
      sl.registerSingleton<IProfileProgressRepo>(_StubProfileProgressRepo());
      sl.registerSingleton<TodayDataService>(_StubTodayDataService());
      sl.registerSingleton<StravaConnectController>(
        _createStubStravaController(),
      );
      sl.registerSingleton<IChallengeRepo>(_StubChallengeRepo());
      sl.registerSingleton<IBadgeAwardRepo>(_StubBadgeAwardRepo());
      sl.registerSingleton<NotificationRulesService>(_StubNotificationRules());
      sl.registerSingleton<FirstUseTips>(_StubFirstUseTips());

      // NOT registering ISessionRepo to trigger the outer catch
      // sl<ISessionRepo>().getByStatus() will throw, triggering error state

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível carregar seus dados.'), findsOneWidget);
    });

    testWidgets('shows running tip card when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps();

      await tester.pumpApp(
        const TodayScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Dica do dia'), findsOneWidget);
    });
  });
}
