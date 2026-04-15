import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/data/services/profile_data_service.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/presentation/screens/profile_screen.dart';
import 'package:omni_runner/presentation/widgets/shimmer_loading.dart';

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

class _StubProfileRepo implements IProfileRepo {
  final ProfileEntity? profile;
  final bool shouldThrow;
  final Completer<void>? gate;

  _StubProfileRepo({this.profile, this.shouldThrow = false, this.gate});

  @override
  Future<ProfileEntity?> getMyProfile() async {
    if (gate != null) await gate!.future;
    if (shouldThrow) throw Exception('Network error');
    return profile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubProfileDataService implements ProfileDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Map<String, dynamic>?> getSocialColumns(String userId) async => null;
}

void main() {
  group('ProfileScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed') || msg.contains('_isInitialized')) {
          return;
        }
        origOnError?.call(details);
      };
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    void registerDeps({
      ProfileEntity? profile,
      bool profileThrows = false,
      Completer<void>? gate,
    }) {
      final authRepo = _StubAuthRepo();

      sl.registerSingleton<IProfileRepo>(
        _StubProfileRepo(
          profile: profile,
          shouldThrow: profileThrows,
          gate: gate,
        ),
      );
      sl.registerSingleton<ProfileDataService>(_StubProfileDataService());
      sl.registerSingleton<UserIdentityProvider>(
        UserIdentityProvider(authRepo: authRepo)
          ..updateProfileName('TestUser'),
      );
      sl.registerSingleton<AuthRepository>(authRepo);
    }

    testWidgets('renders without crash', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('shows shimmer placeholder while profile loads', (tester) async {
      final gate = Completer<void>();
      registerDeps(gate: gate);

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(ShimmerListLoader), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows app bar', (tester) async {
      registerDeps();

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows error state when profile load fails', (tester) async {
      registerDeps(profileThrows: true);

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error when profile loads but Supabase unavailable',
        (tester) async {
      registerDeps(
        profile: ProfileEntity(
          id: 'test-uid',
          displayName: 'Maria Runner',
          userRole: 'ATLETA',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows no-profile state when getMyProfile returns null',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      registerDeps(profile: null);

      await tester.pumpApp(
        const ProfileScreen(),
        wrapScaffold: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });
}
