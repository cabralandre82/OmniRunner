import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/deep_links/deep_link_handler.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/domain/entities/profile_entity.dart';
import 'package:omni_runner/domain/repositories/i_profile_repo.dart';
import 'package:omni_runner/presentation/screens/challenge_join_screen.dart';
import 'package:omni_runner/presentation/screens/home_screen.dart';
import 'package:omni_runner/presentation/screens/join_assessoria_screen.dart';
import 'package:omni_runner/presentation/screens/login_screen.dart';
import 'package:omni_runner/presentation/screens/onboarding_role_screen.dart';
import 'package:omni_runner/presentation/screens/staff_setup_screen.dart';
import 'package:omni_runner/presentation/screens/welcome_screen.dart';

/// Single entry-point guard that routes users based on auth + onboarding state.
///
/// Flow:
///   No session / anonymous → [WelcomeScreen] → [LoginScreen]
///   Session + NEW → [OnboardingRoleScreen]
///   Session + ROLE_SELECTED + ATLETA → [JoinAssessoriaScreen]
///   Session + ROLE_SELECTED + STAFF → [StaffSetupScreen]
///   Session + READY → [HomeScreen]
///   Mock mode → [HomeScreen] (skip all gates)
///
/// Invite link handling:
///   - Not logged in → persists code, applies after login
///   - Onboarding ATLETA → passed as initialCode to [JoinAssessoriaScreen]
///   - READY user → auto-join with confirmation dialog
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _GateDestination {
  loading,
  welcome,
  login,
  onboarding,
  joinAssessoria,
  staffSetup,
  home,
}

class _AuthGateState extends State<AuthGate> {
  static const _tag = 'AuthGate';

  _GateDestination _dest = _GateDestination.loading;
  OnboardingState _onboardingState = OnboardingState.newUser;
  String? _userRole;
  String? _pendingInviteCode;
  StreamSubscription<DeepLinkAction>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = sl<DeepLinkHandler>().actions.listen(_onDeepLink);
    _resolve();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Deep link handling ──────────────────────────────────────────────────

  void _onDeepLink(DeepLinkAction action) {
    if (action is ChallengeAction) {
      _navigateToChallenge(action.challengeId);
      return;
    }

    if (action is! InviteAction) return;

    final code = action.code;
    _pendingInviteCode = code;

    if (_dest == _GateDestination.home) {
      _autoJoinFromHome(code);
    } else if (_dest == _GateDestination.welcome) {
      _go(_GateDestination.login);
    }
  }

  void _navigateToChallenge(String challengeId) {
    if (!mounted) return;
    if (_dest != _GateDestination.home) return;

    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChallengeJoinScreen(challengeId: challengeId),
    ));
  }

  /// Auto-join flow for READY users already on the home screen.
  /// Looks up the group, shows a confirmation dialog, then joins.
  Future<void> _autoJoinFromHome(String code) async {
    if (!mounted) return;

    // Clear persisted code — we're handling it now.
    _pendingInviteCode = null;
    sl<DeepLinkHandler>().consumePendingInvite();

    final client = Supabase.instance.client;

    try {
      // Lookup group by invite code
      final res = await client.rpc(
        'fn_lookup_group_by_invite_code',
        params: {'p_code': code},
      );
      final list = res as List<dynamic>;

      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Código de convite inválido ou assessoria não aceita novos membros.',
            ),
          ),
        );
        return;
      }

      final data = list.first as Map<String, dynamic>;
      final groupId = data['id'] as String;
      final groupName = data['name'] as String? ?? 'Assessoria';

      if (!mounted) return;

      // Confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Entrar na assessoria?'),
          content: Text(groupName),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      await client.rpc(
        'fn_switch_assessoria',
        params: {'p_new_group_id': groupId},
      );

      AppLogger.info('Auto-joined group $groupId from invite link', tag: _tag);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Você entrou na assessoria $groupName!'),
          backgroundColor: Colors.green,
        ),
      );

      // Re-resolve to refresh the home screen state
      setState(() => _dest = _GateDestination.loading);
      _resolve();
    } catch (e) {
      AppLogger.error('Auto-join failed: $e', tag: _tag, error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível entrar na assessoria.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── State resolution ────────────────────────────────────────────────────

  Future<void> _resolve() async {
    // Mock mode: go straight to home (offline development).
    if (!AppConfig.isSupabaseReady) {
      _go(_GateDestination.home);
      return;
    }

    final identity = sl<UserIdentityProvider>();
    final authRepo = identity.authRepository;

    // No authenticated user at all → show welcome screen.
    if (!authRepo.isSignedIn) {
      _go(_GateDestination.welcome);
      return;
    }

    // Anonymous users must go through login to access the full app.
    if (identity.isAnonymous) {
      _go(_GateDestination.welcome);
      return;
    }

    // Check for a persisted pending invite code (survives OAuth redirects).
    final handler = sl<DeepLinkHandler>();
    final persistedCode = await handler.consumePendingInvite();
    if (persistedCode != null) {
      _pendingInviteCode ??= persistedCode;
    }

    // Authenticated non-anonymous user: check onboarding state.
    try {
      final profile = await sl<IProfileRepo>().getMyProfile();
      if (profile == null) {
        AppLogger.warn('Profile not found for ${identity.userId}', tag: _tag);
        _onboardingState = OnboardingState.newUser;
        _go(_GateDestination.onboarding);
        return;
      }

      _onboardingState = profile.onboardingState;
      _userRole = profile.userRole;

      if (profile.isOnboardingComplete) {
        if (_pendingInviteCode != null) {
          final code = _pendingInviteCode!;
          _pendingInviteCode = null;
          _go(_GateDestination.home);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoJoinFromHome(code);
          });
        } else {
          _go(_GateDestination.home);
        }
      } else if (profile.onboardingState == OnboardingState.roleSelected &&
          profile.userRole == 'ATLETA') {
        _go(_GateDestination.joinAssessoria);
      } else if (profile.onboardingState == OnboardingState.roleSelected &&
          profile.userRole == 'ASSESSORIA_STAFF') {
        _go(_GateDestination.staffSetup);
      } else {
        _go(_GateDestination.onboarding);
      }
    } catch (e) {
      AppLogger.error('AuthGate profile fetch failed: $e', tag: _tag, error: e);
      _go(_GateDestination.home);
    }
  }

  void _go(_GateDestination d) {
    if (!mounted) return;
    setState(() => _dest = d);
  }

  void _onLoginSuccess() {
    sl<UserIdentityProvider>().refresh();
    setState(() => _dest = _GateDestination.loading);
    _resolve();
  }

  void _onOnboardingComplete() {
    setState(() => _dest = _GateDestination.loading);
    _resolve();
  }

  Future<void> _onBackToLogin() async {
    await sl<UserIdentityProvider>().authRepository.signOut();
    _go(_GateDestination.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _dest == _GateDestination.onboarding ||
        _dest == _GateDestination.joinAssessoria ||
        _dest == _GateDestination.staffSetup;

    final child = switch (_dest) {
      _GateDestination.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      _GateDestination.welcome => WelcomeScreen(
          onStart: () => _go(_GateDestination.login),
        ),
      _GateDestination.login => LoginScreen(
          onSuccess: _onLoginSuccess,
          hasPendingInvite: _pendingInviteCode != null,
        ),
      _GateDestination.onboarding => OnboardingRoleScreen(
          initialState: _onboardingState,
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.joinAssessoria => JoinAssessoriaScreen(
          initialCode: _pendingInviteCode,
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.staffSetup => StaffSetupScreen(
          onComplete: _onOnboardingComplete,
          onBack: _onBackToLogin,
        ),
      _GateDestination.home => HomeScreen(userRole: _userRole),
    };

    if (canGoBack) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBackToLogin();
        },
        child: child,
      );
    }
    return child;
  }
}
